#!/usr/bin/env ruby
require 'yaml'
require 'optparse'

# Parse command-line arguments
options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: ruby merge_yaml.rb [options]"

  opts.on("-s", "--source SOURCE", "Source YAML file") do |source|
    options[:source] = source
  end

  opts.on("-d", "--destination DESTINATION", "Destination YAML file") do |destination|
    options[:destination] = destination
  end
end.parse!

# Ensure both source and destination files are provided
if options[:source].nil? || options[:destination].nil?
  puts "Both source and destination files must be provided!"
  exit 1
end

source_file = options[:source]
destination_file = options[:destination]

# Load source and destination YAML files
source_data = YAML.load_file(source_file)
destination_data = YAML.load_file(destination_file)

# Merge `:tests` sections
source_tests = source_data[:tests] || {}
destination_tests = destination_data[:tests] || {}

# Add source tests to destination tests
merged_tests = destination_tests.merge(source_tests)

# Update the destination data with the merged tests
destination_data[:tests] = merged_tests

# Save the updated destination YAML file
File.open(destination_file, 'w') do |file|
  file.write(destination_data.to_yaml)
end

puts "Tests merged successfully from '#{source_file}' to '#{destination_file}'!"