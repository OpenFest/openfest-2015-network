#!/usr/local/bin/ruby
$stdout.sync = true

COLLECTD_INTERVAL = ENV['COLLECTD_INTERVAL'] ? ENV['COLLECTD_INTERVAL'].to_i : 10
COLLECTD_HOSTNAME = ENV['COLLECTD_HOSTNAME'] || 'localhost'

class Stats
  def initialize(stats, interval)
    @stats = stats
    @interval = interval
  end

  def histogram
    @stats.select { |key, _| key.include? 'histogram' }.values.map(&:to_i)
  end

  def histogram_percent
    total_queries = histogram.reduce(&:+).to_f
    histogram.map { |value| value * 100 / total_queries }
  end

  def current_time
    @stats['time.now'].split('.').first
  end

  def putval(name, data)
    "PUTVAL #{COLLECTD_HOSTNAME}/unbound/#{name} interval=#{@interval} #{current_time}:#{data.join(':')}"
  end

  def thread_stats
    @stats.select { |key, _| key.include? 'histogram' }.values.map(&:to_i)
  end

  # msg.cache.count=1059
  # rrset.cache.count=913
  # infra.cache.count=7
  # key.cache.count=0
  def cache_counts
    [@stats['msg.cache.count'], @stats['rrset.cache.count'], @stats['infra.cache.count'], @stats['key.cache.count']]
  end

  # thread1.recursion.time.avg=0.079665
  # thread1.recursion.time.median=0.0541417
  def recursion_times
    stats = @stats.select{ |key, _| key.include? 'recursion.time' }
    result = stats.group_by { |key, value| key.split('.').first }
    result.each { |key, value| result[key] = Hash[value] }
    result.each { |key, value| result[key] = result[key].values }
    result
  end

  # thread0.requestlist.avg=1.07819
  # thread0.requestlist.max=8
  # thread0.requestlist.overwritten=0
  # thread0.requestlist.exceeded=0
  # thread0.requestlist.current.all=0
  # thread0.requestlist.current.user=0
  def request_list
    stats = @stats.select{ |key, _| key.include? 'requestlist' }
    result = stats.group_by { |key, value| key.split('.').first }
    result.each { |key, value| result[key] = Hash[value] }
    result.each { |key, value| result[key] = result[key].values }
    result
  end

  # thread0.num.queries=2903
  # thread0.num.cachehits=1445
  # thread0.num.cachemiss=1458
  # thread0.num.prefetch=0
  # thread0.num.recursivereplies=1458
  def requests
    stats = @stats.select{ |key, _| key =~ /^(thread.*|total)\.num/ }
    result = stats.group_by { |key, value| key.split('.').first }
    result.each { |key, value| result[key] = Hash[value] }
    result.each { |key, value| result[key] = result[key].values }
    result
  end

  # num.query.type.A=1347
  # num.query.type.PTR=1966
  # num.query.type.AAAA=889
  # num.query.type.SRV=5
  # num.query.class.IN=4207
  # num.query.opcode.QUERY=4207
  # num.query.tcp=0
  # num.query.tcpout=0
  # num.query.ipv6=1505
  # num.query.flags.QR=0
  # num.query.flags.AA=0
  # num.query.flags.TC=0
  # num.query.flags.RD=4207
  # num.query.flags.RA=0
  # num.query.flags.Z=0
  # num.query.flags.AD=0
  # num.query.flags.CD=0
  # num.query.edns.present=2126
  # num.query.edns.DO=19
  def queries
    @stats.select { |key, _| key =~ /^num\.query/ }.values
  end

  # num.answer.rcode.NOERROR=3674
  # num.answer.rcode.FORMERR=0
  # num.answer.rcode.SERVFAIL=40
  # num.answer.rcode.NXDOMAIN=493
  # num.answer.rcode.NOTIMPL=0
  # num.answer.rcode.REFUSED=0
  # num.answer.rcode.nodata=310
  # num.answer.secure=0
  # num.answer.bogus=0
  def answers
    @stats.select { |key, _| key =~ /^num\.answer/ }.values
  end

  # mem.total.sbrk=0
  # mem.cache.rrset=184663
  # mem.cache.message=168614
  # mem.mod.iterator=16472
  # mem.mod.validator=33156
  def memory
    @stats.select { |key, _| key =~ /^mem/ }
  end

  def to_putvals
    result = ""
    result += putval('histogram_percent', histogram_percent)
    result += "\n"
    result += putval('histogram', histogram)
    result += "\n"
    result += putval('cache_counts', cache_counts)
    result += "\n"

    recursion_times.each do |key, value|
      result += putval("recursion_times-#{key}", value)
      result += "\n"
    end

    request_list.each do |key, value|
      result += putval("request_list-#{key}", value)
      result += "\n"
    end

    requests.each do |key, value|
      result += putval("unbound_requests-#{key}", value)
      result += "\n"
    end

    result += putval('unbound_queries', queries)
    result += "\n"

    result += putval('unbound_answers', answers)
    result += "\n"

    memory.each do |key, value|
      result += putval("memory-#{key.gsub('.', '_')}", [value])
      result += "\n"
    end

    result
  end
end

# time.up=5571.770754
# time.elapsed=5571.770754
# num.rrset.bogus=0
# unwanted.queries=0
# unwanted.replies=0

loop do
  stats = Stats.new(Hash[`/usr/local/sbin/unbound-control stats`
                          .split("\n").map { |row| row.split '=' }], COLLECTD_INTERVAL)
  puts stats.to_putvals

  sleep COLLECTD_INTERVAL
end
