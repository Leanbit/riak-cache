require 'yaml'
require 'riak'
require 'active_support/version'
require 'active_support/cache'

module Riak
  # An ActiveSupport::Cache::Store implementation that uses Riak.
  # Compatible only with ActiveSupport version 3 or greater.
  class CacheStore < ActiveSupport::Cache::Store
    attr_accessor :client

    # Creates a Riak-backed cache store.
    def initialize(options = {})
      super
      @bucket_name = options.delete(:bucket) || '_cache'
      @n_value = options.delete(:n_value) || 2
      @r = options.delete(:r) || 1
      @w = options.delete(:w) || 1
      @dw = options.delete(:dw) || 0
      @rw = options.delete(:rw) || "quorum"
      @client = Riak::Client.new(options)
      set_bucket_defaults
    end

    def bucket
      @bucket ||= @client.bucket(@bucket_name)
    end

    def delete_matched(matcher, options={})
      instrument(:delete_matched, matcher) do
        bucket.keys do |keys|
          keys.grep(matcher).each do |k|
            bucket.delete(k)
          end
        end
      end
    end

    # Increments an already existing integer value that is stored in the cache.
    # If the key is not found nothing is done.
    def increment(name, amount = 1, options = nil)
      modify_value(name, amount, options)
    end

    # Decrements an already existing integer value that is stored in the cache.
    # If the key is not found nothing is done.
    def decrement(name, amount = 1, options = nil)
      modify_value(name, -amount, options)
    end

    protected
    def set_bucket_defaults
      begin
        new_values = {}
        new_values['n_val'] = @n_value unless bucket.n_value == @n_value
        new_values['r']     = @r       unless bucket.r == @r
        new_values['w']     = @w       unless bucket.w == @w
        new_values['dw']    = @dw      unless bucket.dw == @dw
        new_values['rw']    = @rw      unless bucket.rw == @rw
        bucket.props = new_values      unless new_values.empty?
      rescue
      end
    end

    def write_entry(key, value, options={})
      object = bucket.get_or_new(key)
      object.content_type = 'application/yaml'
      object.data = value
      object.store
    end

    def read_entry(key, options={})
      begin
        bucket.get(key).data
      rescue Riak::FailedRequest => fr
        raise fr unless fr.not_found?
        nil
      end
    end

    def delete_entry(key, options={})
      bucket.delete(key)
      nil
    end

    def modify_value(name, amount, options)
      begin
        cached_entry = read_entry(name, options)
        new_value = cached_entry.value + amount
        cache_entry = ActiveSupport::Cache::Entry.new(cached_entry.value + amount)
        write_entry(name, cache_entry) rescue nil
        new_value
      rescue
        nil
      end
    end

  end
end
