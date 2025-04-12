require 'rake/testtask'

desc 'Run all tests'
task :test do
  $LOAD_PATH.unshift('lib')
  Dir.glob('./test/**/*_test.rb').each { |file| require file }
end

namespace :test do
  desc 'Run MoogLead tests'
  task :moog_lead do
    ruby 'test/presets/moog_lead_test.rb'
  end

  desc 'Run frequency analysis tests'
  task :frequency do
    ruby 'test/presets/frequency_test.rb'
  end
end

task default: :test
