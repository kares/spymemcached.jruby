require 'spymemcached-2.11.4.jar'
require 'spymemcached_adapter.jar'
require 'spymemcached_adapter'
require 'digest/md5'

#
# Memcached client Spymemcached JRuby extension
#
class Spymemcached
  class Error < StandardError; end
  class TimeoutError < Error; end

  ESCAPE_KEY_CHARS = /[\x00-\x20%\x7F-\xFF]/n
  # default options for client
  DEFAULT_OPTIONS = {
    :timeout => 0.5, # second
    :binary => true
  }

  # Accepts a list of +servers+ and a list of +options+.
  # The +servers+ can be either strings of the form "hostname:port" or
  # one string format as "<hostname>:<port>,<hostname>:<port>".
  # Use KetamaConnectionFactory as Spymemcached MemcachedClient connection factory.
  # See Spymemcached document for details.
  # Different with Ruby memcache clients (e.g. Dalli), there is no raw option for operations.
  #
  # Valid +options+ are:
  #
  #   [:namespace]   Prepends this value to all keys added or retrieved.
  #   [:timeout]     Time to use as the socket read timeout, seconds.  Defaults to 0.5 sec.
  #   [:binary]      Talks binary protocol with Memcached server. Default to true.
  #
  # Logger: see Spymemcached for how to turn on detail log
  #
  def initialize(servers=['localhost:11211'], options={})
    @servers, @options = Array(servers).join(','), DEFAULT_OPTIONS.merge(options)
    @client = SpymemcachedAdapter.new(@servers, @options)
    @namespace = if @options[:namespace]
      @options[:namespace].is_a?(Proc) ? @options[:namespace] : lambda { @options[:namespace] }
    end
    at_exit { shutdown }
  end

  def fetch(key, ttl=0, &block)
    val = get(key)
    if val.nil? && block_given?
      val = yield
      add(key, val, ttl)
    end
    val
  end

  def get(key)
    @client.get(encode(key))
  end
  alias :[] :get

  def get_multi(*keys)
    key_map = Hash[keys.flatten.compact.map {|k| [encode(k), k]}]
    Hash[@client.get_multi(key_map.keys).map {|k, v| [key_map[k], v]}]
  end

  def add(key, value, ttl=0)
    @client.add(encode(key), value, ttl)
  end

  def set(key, value, ttl=0)
    @client.set(encode(key), value, ttl)
  end
  alias :[]= :set

  def cas(key, ttl=0, &block)
    @client.cas(encode(key), ttl, &block)
  end

  def replace(key, value, ttl=0)
    @client.replace(encode(key), value, ttl)
  end

  def delete(key)
    @client.delete(encode(key))
  end

  def incr(key, by=1)
    @client.incr(encode(key), by)
  end

  def decr(key, by=1)
    @client.decr(encode(key), by)
  end

  def append(key, value)
    @client.append(encode(key), value)
  end

  def prepend(key, value)
    @client.prepend(encode(key), value)
  end

  def touch(key, ttl=0)
    @client.touch(encode(key), ttl)
  end

  def stats
    @client.stats
  end

  def version
    @client.version
  end

  def flush_all
    @client.flush_all
  end
  alias :flush :flush_all
  alias :clear :flush_all

  def shutdown
    @client.shutdown
  end

  # compatible api with Rails 2.3 MemcacheStore
  # ActionController::Base.cache_store = :mem_cache_store, Spymemcached.new(servers).rails23
  def rails23
    require 'spymemcached/rails23'
    Rails23.new(self)
  end

  private
  def encode(key)
    escape_key(namespace ? "#{namespace.call}:#{key}" : key)
  end

  def namespace
    @namespace
  end

  # Memcache keys are binaries. So we need to force their encoding to binary
  # before applying the regular expression to ensure we are escaping all
  # characters properly.
  def escape_key(key)
    key = key.to_s.dup
    key = key.force_encoding(Encoding::ASCII_8BIT) if defined?(Encoding)
    key = key.gsub(ESCAPE_KEY_CHARS){ |match| "%#{match.bytes.to_a[0].to_s(16).upcase}" }
    key = "#{key[0, 213]}:md5:#{Digest::MD5.hexdigest(key)}" if key.size > 250
    key
  end

end
