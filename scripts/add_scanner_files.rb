#!/usr/bin/env ruby
# scripts/add_scanner_files.rb
#
# Adds ios/Runner/Scanner/*.swift to the Runner Xcode target and
# sets the iOS deployment target to 17.0 in all build configurations.

require 'xcodeproj'

PROJECT_PATH = 'ios/Runner.xcodeproj'
SCANNER_DIR  = 'ios/Runner/Scanner'
DEPLOYMENT   = '17.0'

project = Xcodeproj::Project.open(PROJECT_PATH)
target  = project.targets.find { |t| t.name == 'Runner' }
abort("ERROR: Could not find Runner target") unless target

# ── Deployment target ────────────────────────────────────────────────────────
[project.build_configuration_list, target.build_configuration_list].each do |list|
  list.build_configurations.each do |config|
    config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = DEPLOYMENT
  end
end
puts "Deployment target set to iOS #{DEPLOYMENT}"

# ── Scanner group ────────────────────────────────────────────────────────────
runner_group = project.main_group.find_subpath('Runner', false)
abort("ERROR: Runner group not found in project") unless runner_group

scanner_group = runner_group.find_subpath('Scanner', false)
unless scanner_group
  scanner_group = runner_group.new_group('Scanner', 'Scanner')
  puts "Created Scanner group"
end

# ── Add Swift source files ────────────────────────────────────────────────────
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

project.save
puts "\nXcode project saved — Scanner files linked to Runner target."
