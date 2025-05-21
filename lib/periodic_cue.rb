class PeriodicCue
  def initialize(*interval)
    @interval = interval.cycle
    @time = nil
  end

  def sleep_until(t)
    sleep((t - Time.now).clamp(0..))
  end

  def sync
    @time += @interval.next
    sleep_until(@time)
  end

  def start
    @time = Time.now unless @time
  end
end

if __FILE__ == $0
  cue = PeriodicCue.new(0.8, 0.2)
  cue.start
  s = t = Time.now
  10.times do |n|
    puts (n % 2 == 0) ? 'on' : 'off'
    cue.sync
    last = t
    t = Time.now
    puts "%.3f" % (t - s)
  end
end
