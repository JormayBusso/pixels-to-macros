#!/usr/bin/env ruby
# scripts/add_scanner_files.rb
#
# Adds ios/Runner/Scanner/*.swift to the Runner Xcode target,
# links required system frameworks, and sets the iOS deployment target to 17.0.

require 'xcodeproj'

PROJECT_PATH = 'ios/Runner.xcodeproj'
SCANNER_DIR  = 'ios/Runner/Scanner'
DEPLOYMENT   = '17.0'
# RealityKit + SceneKit are required for the live 3-D food-object preview
# (LiDAR mesh on Pro, extruded-mask mesh on non-Pro). Metal backs the renderer.
FRAMEWORKS   = %w[ARKit RealityKit SceneKit Metal CoreML Vision CoreVideo AVFoundation].freeze
# Compiled CoreML segmentation model that must ship inside the app bundle.
# Produced by: training/export_coreml.py + `xcrun coremlcompiler compile`.
MODEL_NAME   = 'FoodSegmentation.mlmodelc'
MODEL_PATH   = "ios/Runner/#{MODEL_NAME}"

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

# ── Bundle the compiled CoreML model as an app resource ───────────────────────
# Without this the segmentation model is missing from the bundle at runtime and
# every scan fails with `FoodSegmentation.mlmodelc not found in bundle`.
if File.exist?(MODEL_PATH)
  resources_phase = target.resources_build_phase
  already_bundled = resources_phase.files.any? do |f|
    f.file_ref&.display_name == MODEL_NAME
  end
  if already_bundled
    puts "  (skip) #{MODEL_NAME} already bundled"
  else
    model_ref = runner_group.new_file(MODEL_NAME)
    resources_phase.add_file_reference(model_ref)
    puts "  Bundled #{MODEL_NAME}"
  end
else
  puts "  WARNING: #{MODEL_PATH} not found — export & compile the model first:"
  puts "    python training/export_coreml.py --checkpoint training/output/best.pth"
  puts "    xcrun coremlcompiler compile training/output/FoodSegmentation.mlpackage ios/Runner/"
end

project.save
puts "\nXcode project saved — Scanner files and frameworks linked to Runner target."
