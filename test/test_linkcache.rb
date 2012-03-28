require './lib/tki-linkcheck'
Bundler.require(:test)

require 'minitest/autorun'

class TestLinkCache < MiniTest::Unit::TestCase
  def setup
    $redis = MockRedis.new
  end
  
  
  def teardown
    load './lib/tki-linkcheck/redis.rb'
    $options.linkcache_time = 60
  end

  
  def test_adding_link_to_cache
    LinkCache.add 'http://a.com'
    assert LinkCache.passed? 'http://a.com'
  end
  
  
  def test_non_urls_ignored
    LinkCache.add 'abc'
    refute LinkCache.passed? 'abc'
  end
  
  
  def test_cache_idempotent
    LinkCache.add 'http://thing.com'
    LinkCache.add 'http://thing.com'
    LinkCache.add 'http://thing.com'
    assert_equal 1, $redis.scard(LinkCache.send(:class_variable_get, :@@key))
  end
  
  
  def test_cache_is_flushable
    $options.linkcache_time = 0
    LinkCache.add 'http://thing.com'
    LinkCache.add 'http://thing.com/a'
    assert LinkCache.passed? 'http://thing.com'
    assert LinkCache.passed? 'http://thing.com/a'
    LinkCache.flush
    refute LinkCache.passed? 'http://thing.com'
    refute LinkCache.passed? 'http://thing.com/a'
  end
  
  
  def test_cache_is_not_flushable_if_recently_active
    $options.linkcache_time = 60
    LinkCache.add 'http://thing.com'
    assert LinkCache.passed? 'http://thing.com'
    LinkCache.flush
    assert LinkCache.passed? 'http://thing.com'
  end
  
  
  def test_forced_flush_ignores_recency
    $options.linkcache_time = 60
    LinkCache.add 'http://thing.com'
    LinkCache.force_flush
    refute LinkCache.passed? 'http://thing.com'
  end
end
