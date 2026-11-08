require 'tmpdir'
require 'rbconfig'
require 'stringio'
require_relative 'plan-loop-gate'

def assert(condition, message)
  raise message unless condition
end

def update(gate)
  record = gate.manifest
  yield record
  File.write(gate.manifest_path, JSON.pretty_generate(record))
end

def populate(gate, argv = [RbConfig.ruby, '-e', 'exit 0'])
  update(gate) do |record|
    record['scope'] = ['source.txt']
    record['criteria'] = [{
      'id' => 'C1', 'outcome' => 'Change source behavior',
      'implementation' => ['source.txt'], 'checks' => ['check'], 'assessment' => 'PASS'
    }]
    record['checks'] = [{ 'id' => 'check', 'argv' => argv }]
  end
end

def blocked(gate, fragment)
  result = gate.stop
  assert(result['decision'] == 'block' && result['reason'].include?(fragment), "Expected block mentioning #{fragment}: #{result}")
end

def hook(root, action, payload)
  script = File.expand_path('plan-loop-gate.rb', __dir__)
  output, error, status = Open3.capture3(RbConfig.ruby, script, action, stdin_data: JSON.generate(payload), chdir: root)
  assert(status.success?, "Hook exited non-zero: #{error}")
  action == 'stop' ? JSON.parse(output) : output
end

tests = {
  'inactive sessions pass without a manifest' => lambda { |root|
    assert(PlanLoopGate.new(root, 'inactive').stop == {}, 'Inactive gate blocked')
  },
  'activation blocks missing acceptance scope' => lambda { |root|
    gate = PlanLoopGate.new(root, 'missing')
    gate.begin_request('PLAN implement')
    blocked(gate, 'scope')
  },
  'successful checks alone do not replace assessment or delivery' => lambda { |root|
    gate = PlanLoopGate.new(root, 'success')
    gate.begin_request('PLAN implement')
    populate(gate)
    blocked(gate, 'Missing executed check')
    gate.run_check('check')
    blocked(gate, 'assessment is missing')
    gate.assess('Read diff against C1 and checked error behavior')
    blocked(gate, 'Delivery is not complete')
    update(gate) { |r| r['disposition'] = 'complete' }
    assert(gate.stop == {}, 'Complete gate blocked')
    gate.follow_up('Explain the result')
    File.write(File.join(root, 'source.txt'), 'unrelated later edit')
    assert(gate.stop == {}, 'Completed request affected subsequent non-PLAN turn')
  },
  'source edits invalidate checks and assessment' => lambda { |root|
    gate = PlanLoopGate.new(root, 'stale')
    gate.begin_request('PLAN implement')
    populate(gate)
    gate.run_check('check')
    gate.assess('Reviewed C1')
    update(gate) { |r| r['disposition'] = 'complete' }
    File.write(File.join(root, 'source.txt'), 'changed')
    blocked(gate, 'stale check')
    gate.run_check('check')
    blocked(gate, 'assessment is missing or stale')
  },
  'manifest edits and follow-ups invalidate existing receipts' => lambda { |root|
    gate = PlanLoopGate.new(root, 'contract')
    gate.begin_request('PLAN implement')
    populate(gate)
    gate.run_check('check')
    update(gate) { |r| r['criteria'][0]['outcome'] = 'Different outcome' }
    blocked(gate, 'stale check')
    gate.run_check('check')
    gate.follow_up('Also handle the edge case')
    blocked(gate, 'stale check')
  },
  'input changes during a check cannot create current evidence' => lambda { |root|
    gate = PlanLoopGate.new(root, 'during-check')
    gate.begin_request('PLAN implement')
    populate(gate, [RbConfig.ruby, '-e', "File.write('source.txt', 'modified during check')"])
    begin
      gate.run_check('check')
      raise 'Changing inputs passed verification'
    rescue PlanLoopGate::Invalid => error
      assert(error.message.include?('Inputs changed'), error.message)
    end
    blocked(gate, 'stale check')
  },
  'failed and missing commands record failures instead of passing' => lambda { |root|
    [[RbConfig.ruby, '-e', 'exit 7'], ['/nonexistent-plan-loop-check']].each_with_index do |argv, index|
      gate = PlanLoopGate.new(root, "failed-#{index}")
      gate.begin_request('PLAN implement')
      populate(gate, argv)
      begin
        gate.run_check('check')
        raise 'Failed command passed'
      rescue PlanLoopGate::Invalid => error
        assert(error.message.include?('failed'), error.message)
      end
      blocked(gate, 'Failed or stale check')
    end
  },
  'commands are argv vectors rather than shell text' => lambda { |root|
    gate = PlanLoopGate.new(root, 'argv')
    gate.begin_request('PLAN implement')
    populate(gate, ['printf', '%s', '$(touch unexpected-file); echo injected'])
    gate.run_check('check')
    assert(!File.exist?(File.join(root, 'unexpected-file')), 'Shell content was interpreted')
  },
  'criteria, commands, and repository paths are validated' => lambda { |root|
    [
      ->(r) { r['criteria'] = [] },
      ->(r) { r['checks'] = [] },
      ->(r) { r['criteria'][0]['checks'] = ['unknown'] },
      ->(r) { r['criteria'][0]['implementation'] = ['unlisted.txt'] },
      ->(r) { r['checks'][0]['argv'] = ["bad\0command"] },
      ->(r) { r['scope'] = ['../outside'] },
      ->(r) { r['scope'] = [File.join(root, 'source.txt')] },
      ->(r) { r['scope'] = ['.git/config'] }
    ].each_with_index do |change, index|
      gate = PlanLoopGate.new(root, "invalid-#{index}")
      gate.begin_request('PLAN implement')
      populate(gate)
      update(gate, &change)
      assert(gate.stop['decision'] == 'block', "Invalid contract #{index} passed")
    end
    File.symlink('/etc/hosts', File.join(root, 'outside-link'))
    gate = PlanLoopGate.new(root, 'symlink')
    gate.begin_request('PLAN implement')
    populate(gate)
    update(gate) { |r| r['scope'] = ['outside-link'] }
    blocked(gate, 'escapes repository')
  },
  'unassessed criteria cannot be approved' => lambda { |root|
    gate = PlanLoopGate.new(root, 'review')
    gate.begin_request('PLAN implement')
    populate(gate)
    update(gate) { |r| r['criteria'][0]['assessment'] = 'FAIL' }
    gate.run_check('check')
    begin
      gate.assess('Reviewed')
      raise 'FAIL criterion approved'
    rescue PlanLoopGate::Invalid => error
      assert(error.message.include?('not passed'), error.message)
    end
  },
  'blocked and plan-only dispositions allow honest non-completion' => lambda { |root|
    %w[blocked plan-only].each do |disposition|
      gate = PlanLoopGate.new(root, disposition)
      gate.begin_request('PLAN')
      update(gate) { |r| r['disposition'] = disposition }
      blocked(gate, 'reason is required')
      update(gate) { |r| r['reason'] = 'Awaiting device confirmation / requested plan delivered' }
      assert(gate.stop == {}, 'Non-completion report blocked')
    end
  },
  'session isolation and native payloads work' => lambda { |root|
    plain = { 'sessionId' => 'plain', 'cwd' => root, 'prompt' => 'please plan the approach' }
    hook(root, 'prompt', plain)
    assert(hook(root, 'stop', plain) == {}, 'Lowercase plan activated gate')
    native = { 'sessionId' => 'native', 'cwd' => root, 'prompt' => 'PLAN implement' }
    hook(root, 'prompt', native)
    assert(hook(root, 'stop', native)['decision'] == 'block', 'Native gate did not block')
    compat = { 'session_id' => 'compat', 'cwd' => root, 'prompt' => 'use plan-loop' }
    hook(root, 'prompt', compat)
    assert(hook(root, 'stop', compat)['decision'] == 'block', 'Compatible gate did not block')
    assert(PlanLoopGate.new(root, 'native').manifest_path != PlanLoopGate.new(root, 'compat').manifest_path, 'Sessions share state')
    FileUtils.mkdir_p(File.join(root, 'nested'))
    assert(PlanLoopGate.new(File.join(root, 'nested'), 'native').manifest_path ==
      PlanLoopGate.new(root, 'native').manifest_path, 'Nested cwd changed session scope')
  },
  'malformed hook payloads and manifests block explicitly' => lambda { |root|
    assert(hook(root, 'stop', [])['decision'] == 'block', 'Malformed payload passed')
    assert(hook(root, 'stop', { 'cwd' => root })['decision'] == 'block', 'Missing session passed')
    assert(hook(root, 'stop', { 'cwd' => nil, 'sessionId' => 'nil-root' })['decision'] == 'block', 'Invalid cwd passed')
    gate = PlanLoopGate.new(root, 'broken')
    gate.begin_request('PLAN implement')
    File.write(gate.manifest_path, '{')
    blocked(gate, 'completion gate:')
  }
}

tests.each do |name, test|
  Dir.mktmpdir('plan-loop-gate-test-') do |root|
    _, error, status = Open3.capture3('git', 'init', '-q', root)
    assert(status.success?, error)
    File.write(File.join(root, 'source.txt'), 'original')
    previous = $stdout
    begin
      $stdout = StringIO.new
      test.call(root)
    ensure
      $stdout = previous
    end
    puts "PASS: #{name}"
  end
end
puts "#{tests.length} scenarios passed"
