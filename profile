#!/usr/bin/env ruby
# Example:
#   tools/profile_requires activesupport/lib/active_support.rb
#   tools/profile_requires activeresource/examples/simple.rb
#   BRANCH=3-0-stable bundle exec ./profile rails/all
abort 'Use REE so you can profile memory and object allocation' unless GC.respond_to?(:enable_stats)

ENV['NO_RELOAD'] ||= '1'
ENV['RAILS_ENV'] ||= 'development'

GC.enable_stats
require 'rubygems'
Gem.source_index
require 'benchmark'

module RequireProfiler
  private
  def require(file, *args) RequireProfiler.profile(file) { super } end
  def load(file, *args) RequireProfiler.profile(file) { super } end

  @depth, @stats = 0, []
  class << self
    attr_accessor :depth
    attr_accessor :stats

    def profile(file)
      stats << [file, depth]
      self.depth += 1
      heap_before, objects_before = GC.allocated_size, ObjectSpace.allocated_objects
      result = nil
      elapsed = Benchmark.realtime { result = yield }
      heap_after, objects_after = GC.allocated_size, ObjectSpace.allocated_objects
      self.depth -= 1
      stats.pop if stats.last.first == file
      stats << [file, depth, elapsed, heap_after - heap_before, objects_after - objects_before] if result
      result
    end
  end
end

GC.start
before = GC.allocated_size
before_gctime, before_gcruns = GC.time, GC.collections
before_rss = `ps -o rss= -p #{Process.pid}`.to_i
before_live_objects = ObjectSpace.live_objects

path = ARGV.shift
if mode = ARGV.shift
  require 'ruby-prof'
  RubyProf.measure_mode = RubyProf.const_get(mode.upcase)
  RubyProf.start
else
  Object.instance_eval { include RequireProfiler }
end

elapsed = Benchmark.realtime { require path }
results = RubyProf.stop if mode

after_gctime, after_gcruns = GC.time, GC.collections
GC.start
after_live_objects = ObjectSpace.live_objects
after_rss = `ps -o rss= -p #{Process.pid}`.to_i
after = GC.allocated_size
usage = (after - before) / 1024.0

if mode
  if printer = ARGV.shift
    RubyProf.const_get("#{printer.to_s.classify}Printer").new(results).print($stdout)
  elsif RubyProf.const_defined?(:CallStackPrinter)
    File.open("#{File.basename(path, '.rb')}.#{mode}.html", 'w') do |out|
      RubyProf::CallStackPrinter.new(results).print(out)
    end
  else
    File.open("#{File.basename(path, '.rb')}.#{mode}.callgrind", 'w') do |out|
      RubyProf::CallTreePrinter.new(results).print(out)
    end
  end
end

RequireProfiler.stats.each do |file, depth, sec, bytes, objects|
  if sec
    puts "%10.2f KB %10d obj %8.1f ms  %s%s" % [bytes / 1024.0, objects, sec * 1000, ' ' * depth, file]
  else
    puts "#{' ' * (42 + depth)}#{file}"
  end
end
puts "%10.2f KB %10d obj %8.1f ms  %d KB RSS  %8.1f ms GC time  %d GC runs" % [usage, after_live_objects - before_live_objects, elapsed * 1000, after_rss - before_rss, (after_gctime - before_gctime) / 1000.0, after_gcruns - before_gcruns]
