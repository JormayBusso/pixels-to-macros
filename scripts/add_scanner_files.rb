#!/usr/bin/env ruby
# scripts/add_scanner_files.rb
#
# Adds ios/Runner/Scanner/*.swift to the Runner Xcode target,
# links required system frameworks, and sets the iOS deployment target to 17.0.

require 'xcodeproj'

PROJECT_PATH = 'ios/Runner.xcodeproj'
SCANNER_DIR  = 'ios/Runner/Scanner'
DEPLOYMENT   = '17.0'
FRAMEWORKS   = %w[ARKit CoreML Vision CoreVideo AVFoundation].freeze

project = Xcodeproj::Project.open(PROJECT_PATH)
target  = project.targets.find { |t| t.name == 'Runner' }
abort("ERROR: Could not find Runner target") unless target

# ── Deployment target ────────────────────────────────────────────────────────
[project.build_configuration_list, target.build_configuration_list].each do |list|
  list.build_configurations.each do |config|
    config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = DEPLOYMENT
    # Silence any strict concurrency warnings that break Flutter+Swift builds
    config.build_settings['SWIFT_STRICT_CONCURRENCY'] = 'minimal'
  end
end
puts "Deployment target set to iOS #{DEPLOYMENT}"

# ── Scanner source group ─────────────────────────────────────────────────────
runner_group = project.main_group.find_subpath('Runner', false)
abort("ERROR: Runner group not found in project") unless runner_group

scanner_group = runner_group.find_subpath('Scanner', false)
unless scanner_group
  scanner_group = runner_group.new_group('Scanner', 'Scanner')
  puts "Created Scanner group"
end

source_phase = target.source_build_phase

Dir.glob("#{SCANNER_DIR}/*.swift").sort.each do |filepath|
  filename = File.basename(filepath)
  already_in_group = scanner_group.files.any? { |f| f.display_name == filename }
  if already_in_group
    puts "  (skip) #{filename} already in group"
    next
  end
  file_ref = scanner_group.new_file(filename)
  source_phase.add_file_reference(file_ref)
  puts "  Added  #{filename}"
end

# ── Link system frameworks ────────────────────────────────────────────────────
frameworks_phase = target.frameworks_build_phase

# Collect existing linked framework names to avoid duplicates
existing = frameworks_phase.files.map { |f| f.file_ref&.path }.compact

FRAMEWORKS.each do |fw|
  fw_path = "System/Library/Frameworks/#{fw}.framework"
  if existing.any? { |p| p.include?(fw) }
    puts "  (skip) #{fw}.framework already linked"
    next
  end

  # Re-use an existing reference in the Frameworks group if present
  fw_ref = project.frameworks_group.files.find { |f| f.path&.include?(fw) }
  unless fw_ref
    fw_ref = project.frameworks_group.new_file(fw_path)
    fw_ref.source_tree = 'SDKROOT'
    fw_ref.last_known_file_type = 'wrapper.framework'
  end

  frameworks_phase.add_file_reference(fw_ref, true)
  puts "  Linked #{fw}.framework"
end

project.save
puts "\nXcode project saved — Scanner files and frameworks linked to Runner target."
