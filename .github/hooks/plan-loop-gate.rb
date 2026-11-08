require 'digest'
require 'fileutils'
require 'json'
require 'open3'

class PlanLoopGate
  class Invalid < StandardError; end

  def initialize(root, session)
    raise Invalid, 'A non-empty session ID is required' unless session.is_a?(String) && !session.empty?
    raise Invalid, 'A non-empty repository cwd is required' unless root.is_a?(String) && !root.empty? && !root.include?("\0")

    @root = File.realpath(root)
    git_dir, error, status = Open3.capture3('git', 'rev-parse', '--absolute-git-dir', chdir: @root)
    raise Invalid, "Cannot locate repository: #{error.strip}" unless status.success?
    top, error, status = Open3.capture3('git', 'rev-parse', '--show-toplevel', chdir: @root)
    raise Invalid, "Cannot locate repository root: #{error.strip}" unless status.success?
    @root = File.realpath(top.strip)

    @directory = File.join(git_dir.strip, 'plan-loop', Digest::SHA256.hexdigest(session))
    @manifest_path = File.join(@directory, 'acceptance.json')
  end

  attr_reader :manifest_path

  def active?
    File.file?(@manifest_path)
  end

  def begin_request(prompt)
    FileUtils.mkdir_p(@directory, mode: 0o700)
    write(@manifest_path, {
      'version' => 1, 'request' => prompt, 'disposition' => 'active',
      'scope' => [], 'criteria' => [],
      'checks' => [{ 'id' => 'diff', 'argv' => ['git', 'diff', '--check'] }]
    })
    @manifest_path
  end

  def follow_up(prompt)
    record = manifest
    raise Invalid, 'Request is missing' unless text?(record['request'])
    if %w[complete inactive plan-only].include?(record['disposition'])
      record['disposition'] = 'inactive'
      write(@manifest_path, record)
      return
    end
    record['request'] += "\nFollow-up: #{prompt}"
    record['disposition'] = 'active'
    record.delete('reason')
    record.delete('review')
    write(@manifest_path, record)
  end

  def manifest
    record = JSON.parse(File.read(@manifest_path))
    raise Invalid, 'Acceptance record must be a version 1 object' unless record.is_a?(Hash) && record['version'] == 1
    record
  end

  def contract(record)
    raise Invalid, 'Request is missing' unless text?(record['request'])
    scope = strings(record['scope'], 'scope')
    scope.each { |path| scoped_path(path) }
    checks = objects(record['checks'], 'checks')
    criteria = objects(record['criteria'], 'criteria')
    [checks, criteria].each do |entries|
      ids = entries.map { |entry| entry['id'] }
      raise Invalid, 'IDs must be unique non-empty strings' unless ids.all? { |id| text?(id) } && ids.uniq == ids
    end
    checks.each { |check| strings(check['argv'], "check #{check['id']} argv") }
    criteria.each do |criterion|
      raise Invalid, "Criterion #{criterion['id']} has no outcome" unless text?(criterion['outcome'])
      locations = strings(criterion['implementation'], "criterion #{criterion['id']} implementation")
      raise Invalid, "Criterion #{criterion['id']} implementation is outside scope" unless (locations - scope).empty?
      ids = strings(criterion['checks'], "criterion #{criterion['id']} checks")
      raise Invalid, "Criterion #{criterion['id']} references an unknown check" unless (ids - checks.map { |c| c['id'] }).empty?
    end
    record
  end

  def fingerprint(record)
    contract(record)
    inputs = record.reject { |key, _| %w[review disposition reason].include?(key) }
    files = record['scope'].sort.map do |path|
      absolute = scoped_path(path)
      [path, File.file?(absolute) ? Digest::SHA256.file(absolute).hexdigest : 'MISSING']
    end
    Digest::SHA256.hexdigest(JSON.generate([inputs, files]))
  end

  def run_check(id)
    record = contract(manifest)
    check = record['checks'].find { |item| item['id'] == id }
    raise Invalid, "Unknown check: #{id}" unless check

    before = fingerprint(record)
    log = File.join(@directory, "#{Digest::SHA256.hexdigest(id)}.log")
    code = nil
    File.open(log, 'w', 0o600) do |output|
      begin
        argv = check['argv']
        pid = Process.spawn([argv.first, argv.first], *argv.drop(1), chdir: @root, out: output, err: output)
        _, status = Process.wait2(pid)
        code = status.exitstatus
      rescue SystemCallError => error
        output.puts "Cannot execute check: #{error.message}"
      end
    end
    current = fingerprint(manifest)
    write(receipt_path(id), { 'fingerprint' => before, 'exit_code' => code, 'log' => log })
    raise Invalid, "Check #{id} failed (exit=#{code.inspect}); see #{log}" unless code == 0
    raise Invalid, "Inputs changed while check #{id} ran; rerun it" unless current == before

    puts JSON.generate({ 'check' => id, 'exit_code' => code, 'log' => log })
  end

  def verify_checks(record)
    digest = fingerprint(record)
    record['checks'].each do |check|
      path = receipt_path(check['id'])
      raise Invalid, "Missing executed check: #{check['id']}" unless File.file?(path)
      receipt = JSON.parse(File.read(path))
      unless receipt.is_a?(Hash) && receipt['exit_code'] == 0 && receipt['fingerprint'] == digest &&
             File.file?(receipt['log'].to_s)
        raise Invalid, "Failed or stale check: #{check['id']}; rerun via the gate"
      end
    end
    digest
  end

  def assess(summary)
    raise Invalid, 'A concrete read-only assessment summary is required' unless text?(summary)
    record = manifest
    digest = verify_checks(record)
    record['criteria'].each do |criterion|
      raise Invalid, "Criterion #{criterion['id']} has not passed assessment" unless criterion['assessment'] == 'PASS'
    end
    record['review'] = { 'fingerprint' => digest, 'summary' => summary }
    write(@manifest_path, record)
    puts 'Assessment recorded; delivery obligations still need completion.'
  end

  def stop
    return {} unless active?

    record = manifest
    return {} if record['disposition'] == 'inactive'
    if %w[blocked plan-only].include?(record['disposition'])
      raise Invalid, 'A concrete blocker or plan-only delivery reason is required' unless text?(record['reason'])
      return {}
    end
    digest = verify_checks(record)
    raise Invalid, 'Read-only assessment is missing or stale' unless record['review'].is_a?(Hash) &&
      record['review']['fingerprint'] == digest && text?(record['review']['summary'])
    raise Invalid, 'Every criterion must have assessment PASS' unless record['criteria'].all? { |c| c['assessment'] == 'PASS' }
    raise Invalid, 'Delivery is not complete; keep pending obligations explicit' unless record['disposition'] == 'complete'

    {}
  rescue Invalid, JSON::ParserError, SystemCallError => error
    { 'decision' => 'block', 'reason' => "Plan-loop completion gate: #{error.message}. Record: #{@manifest_path}. " \
      'Repair missing evidence, or record disposition=blocked with a concrete reason and report incomplete progress.' }
  end

  private

  def text?(value)
    value.is_a?(String) && !value.strip.empty? && !value.include?("\0")
  end

  def strings(value, label)
    raise Invalid, "#{label} must be a non-empty string array" unless value.is_a?(Array) &&
      !value.empty? && value.all? { |item| text?(item) }
    value
  end

  def objects(value, label)
    raise Invalid, "#{label} must be a non-empty object array" unless value.is_a?(Array) &&
      !value.empty? && value.all? { |item| item.is_a?(Hash) }
    value
  end

  def scoped_path(path)
    absolute = File.expand_path(path, @root)
    raise Invalid, "Scope must use repository-relative paths: #{path}" unless !path.start_with?('/') &&
      absolute.start_with?("#{@root}/") && !absolute.start_with?(File.join(@root, '.git') + '/')
    if File.exist?(absolute)
      raise Invalid, "Scope escapes repository or is not a file: #{path}" unless File.realpath(absolute).start_with?("#{@root}/") &&
        File.file?(absolute)
    end
    absolute
  end

  def receipt_path(id)
    File.join(@directory, "#{Digest::SHA256.hexdigest(id)}.json")
  end

  def write(path, data)
    temporary = "#{path}.#{Process.pid}.tmp"
    File.write(temporary, JSON.pretty_generate(data) + "\n", mode: 'w', perm: 0o600)
    File.rename(temporary, path)
  end
end

if $PROGRAM_NAME == __FILE__
  action, session, argument = ARGV
  hook = %w[prompt stop].include?(action)
  begin
    payload = hook ? JSON.parse($stdin.read) : {}
    raise PlanLoopGate::Invalid, 'Hook payload must be an object' unless payload.is_a?(Hash)
    root = payload.fetch('cwd', Dir.pwd)
    session = payload['sessionId'] || payload['session_id'] if hook
    gate = PlanLoopGate.new(root, session)
    case action
    when 'prompt'
      prompt = payload.fetch('prompt')
      raise PlanLoopGate::Invalid, 'Prompt must be a string' unless prompt.is_a?(String)
      if prompt.match?(/(?<![A-Za-z0-9_])PLAN(?![A-Za-z0-9_])|plan-loop/)
        gate.begin_request(prompt)
      elsif gate.active?
        gate.follow_up(prompt)
      end
      puts '{}'
    when 'stop' then puts JSON.generate(gate.stop)
    when 'begin' then puts gate.begin_request(argument || 'Explicit plan-loop invocation')
    when 'status' then puts gate.manifest_path
    when 'run' then gate.run_check(argument)
    when 'assess' then gate.assess(argument)
    else raise PlanLoopGate::Invalid, 'Usage: plan-loop-gate.rb begin|status|run|assess SESSION [PROMPT|CHECK_ID|SUMMARY]'
    end
  rescue PlanLoopGate::Invalid, JSON::ParserError, KeyError, SystemCallError => error
    if hook
      puts JSON.generate({ 'decision' => 'block', 'reason' => "Plan-loop gate error: #{error.message}" })
      if action == 'prompt'
        warn "Plan-loop gate activation failed: #{error.message}"
        exit 2
      end
    else
      warn "Plan-loop gate error: #{error.message}"
      exit 1
    end
  end
end
