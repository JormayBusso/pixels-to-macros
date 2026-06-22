#!/usr/bin/env ruby
# scripts/add_yolo_model.rb
#
# Adds the exported FoodSegYolo.mlmodelc to the Runner target's resources so the
# trained YOLO11-seg model is bundled and YOLOSegmentationService can load it.
# Idempotent: safe to re-run after every export.

require 'xcodeproj'

PROJECT_PATH = 'ios/Runner.xcodeproj'
RESOURCE     = 'FoodSegYolo.mlmodelc'

project = Xcodeproj::Project.open(PROJECT_PATH)
target  = project.targets.find { |t| t.name == 'Runner' }
abort('ERROR: Could not find Runner target') unless target

# Anchor next to the existing model reference so the new file lands in the same
# group with the same <group>-relative path convention.
anchor = project.files.find { |f| f.display_name == 'FoodSegmentation.mlmodelc' }
abort('ERROR: FoodSegmentation.mlmodelc reference not found') unless anchor
group = anchor.parent

if group.files.any? { |f| f.display_name == RESOURCE }
  puts "(skip) #{RESOURCE} already referenced"
else
  ref = group.new_reference(RESOURCE)
  target.resources_build_phase.add_file_reference(ref)
  puts "Added #{RESOURCE} to Runner resources"
end

project.save
puts 'Saved project.'
