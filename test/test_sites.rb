require './lib/tki-linkcheck'
Bundler.require(:test)

require 'minitest/autorun'

class TestSite < MiniTest::Unit::TestCase
  def setup
    $redis = MockRedis.new
    $redis.sadd "#{$options.global_prefix}:sites", 'http://example.com'
    $redis.hset "#{$options.global_prefix}:http://example.com", 'location', 'http://example.com'
    $redis.hset "#{$options.global_prefix}:http://example.com", 'last_checked', Time.at(0).to_i
    @site = Sites.get 'http://example.com'
  end


  def teardown
    load './lib/tki-linkcheck/redis.rb'
  end


  def test_new_sites_can_be_created
    Sites.create :location => 'http://new.example.com'
    assert_includes $redis.smembers("#{$options.global_prefix}:sites"), 'http://new.example.com'
    site = Sites.get 'http://new.example.com'
    assert_equal site.location, 'http://new.example.com'
  end


  def test_successful_creation_returns_site
    assert_kind_of Sites, Sites.create(:location => 'http://new.example.com')
  end


  def test_creation_without_location_fails
    assert_nil Sites.create :irrelevant => 'ok'
  end


  def test_values_set_and_gettable
    assert_equal 'http://example.com', @site.location
    assert_equal "#{Time.at(0).to_i}", @site.last_checked
  end


  def test_arbitrary_properties_storable
    Sites.create :location => 'http://new.example.com', :magic => 'yes'
    assert_equal 'yes', $redis.hget("#{$options.global_prefix}:http://new.example.com", 'magic')
  end


  def test_arbitrary_properties_settable_and_gettable
    site = Sites.create :location => 'http://new.example.com', :magic => 'yes'
    assert_equal 'http://new.example.com', site.location
    assert_equal 'yes', site.magic
  end


  def test_can_get_all_sites
    $redis.sadd "#{$options.global_prefix}:sites", 'http://new.example.com'
    $redis.hset "#{$options.global_prefix}:http://new.example.com", 'location', 'http://new.example.com'
    a = Sites.all
    assert_kind_of Array, a
    assert_equal 2, a.length
    assert_kind_of Sites, a[0]
    assert_kind_of Sites, a[1]
  end


  def test_add_broken_creates_broken_data_sets_and_members
    @site.add_broken('http://example.com/a', 'http://a.com', 'problem1')
    assert_includes $redis.smembers("#{$options.global_prefix}:#{@site.location}:pages"), 'http://example.com/a'
    assert_includes $redis.smembers("#{$options.global_prefix}:#{@site.location}:page:http://example.com/a"), 'http://a.com'
    assert_includes $redis.smembers("#{$options.global_prefix}:#{@site.location}:links"), 'http://a.com'
    assert_includes $redis.smembers("#{$options.global_prefix}:#{@site.location}:link:http://a.com"), 'http://example.com/a'
    assert_includes $redis.smembers("#{$options.global_prefix}:#{@site.location}:problems"), 'problem1'
    assert_includes $redis.smembers("#{$options.global_prefix}:#{@site.location}:problem:problem1"), 'http://a.com'
  end


  def test_broken_count_increments
    @site.add_broken('http://example.com/a', 'http://a.com', :problem1)
    @site.add_broken('http://example.com/b', 'http://b.com', :problem1)
    assert_equal '2', $redis.get("#{$options.global_prefix}:#{@site.location}:count:broken")
  end


  def test_problems_can_be_symbols
    @site.add_broken('http://example.com/a', 'http://a.com', :problem1)
    assert_includes $redis.smembers("#{$options.global_prefix}:#{@site.location}:problems"), 'problem1'
    assert_includes $redis.smembers("#{$options.global_prefix}:#{@site.location}:problem:problem1"), 'http://a.com'
  end


  def test_log_link_increments_checked_count
    @site.log_link 'http://a.com'
    @site.log_link 'http://b.com'
    assert_equal '2', $redis.get("#{$options.global_prefix}:#{@site.location}:count:checked")
  end


  def test_log_page_increments_page_count
    @site.log_page 'http://example.com/a'
    @site.log_page 'http://example.com/b'
    assert_equal '2', $redis.get("#{$options.global_prefix}:#{@site.location}:count:pages")
  end


  def test_add_to_blacklist_adds_to_blacklist
    @site.add_broken('http://example.com/a', 'http://a.com', :problem1)
    @site.add_broken('http://example.com/a', 'http://b.com', :problem1)
    @site.blacklist 'http://b.com'
    set = $redis.sdiff "#{$options.global_prefix}:#{@site.location}:page:http://example.com/a",
                       "#{$options.global_prefix}:#{@site.location}:blacklist"
    refute_includes set, 'http://b.com'
  end


  def test_add_to_blacklist_changes_broken_count
    @site.add_broken('http://example.com/a', 'http://a.com', :problem1)
    @site.add_broken('http://example.com/a', 'http://b.com', :problem1)
    assert_equal 2, @site.broken_links_count
    @site.blacklist 'http://b.com'
    assert_equal 1, @site.broken_links_count
  end


  def test_remove_from_blacklist_changes_broken_count
    @site.add_broken('http://example.com/a', 'http://a.com', :problem1)
    @site.add_broken('http://example.com/a', 'http://b.com', :problem1)
    @site.blacklist 'http://b.com'
    assert_equal 1, @site.broken_links_count
    @site.remove_from_blacklist 'http://b.com'
    assert_equal 2, @site.broken_links_count
  end


  def test_add_to_temp_blacklist_changes_broken_count
    @site.add_broken('http://example.com/a', 'http://a.com', :problem1)
    @site.add_broken('http://example.com/a', 'http://b.com', :problem1)
    assert_equal 2, @site.broken_links_count
    @site.temp_blacklist 'http://b.com'
    assert_equal 1, @site.broken_links_count
  end


  def test_remove_from_temp_blacklist_changes_broken_count
    @site.add_broken('http://example.com/a', 'http://a.com', :problem1)
    @site.add_broken('http://example.com/a', 'http://b.com', :problem1)
    @site.temp_blacklist 'http://b.com'
    assert_equal 1, @site.broken_links_count
    @site.remove_from_temp_blacklist 'http://b.com'
    assert_equal 2, @site.broken_links_count
  end


  def test_links_by_problem_page_returns_expected_structure
    @site.add_broken('http://example.com/a', 'http://a.com', :problem1)
    @site.add_broken('http://example.com/a', 'http://b.com', :problem1)
    @site.add_broken('http://example.com/b', 'http://b.com', :problem1)
    @site.add_broken('http://example.com/c', 'http://c.com', :problem2)
    @site.add_broken('http://example.com/c', 'http://d.com', :problem2)
    @site.add_broken('http://example.com/c', 'http://e.com', :problem3)
    structure = @site.links_by_problem_by_page
    assert_equal 3, structure.length
    assert_kind_of Hash, structure
    assert_kind_of Hash, structure['http://example.com/a']
    assert_kind_of Array, structure['http://example.com/a']['problem1']
    assert_includes structure['http://example.com/a']['problem1'], 'http://b.com'
    assert_includes structure['http://example.com/c']['problem3'], 'http://e.com'
    assert_equal 2, structure['http://example.com/c']['problem2'].length
    assert_equal 1, structure['http://example.com/c']['problem3'].length
  end


  def test_pages_by_blacklisted_link_by_problem_returns_expected_structure
    @site.add_broken('http://example.com/a', 'http://a.com', :problem1)
    @site.add_broken('http://example.com/a', 'http://b.com', :problem1)
    @site.add_broken('http://example.com/b', 'http://b.com', :problem1)
    @site.add_broken('http://example.com/c', 'http://c.com', :problem2)
    @site.add_broken('http://example.com/c', 'http://d.com', :problem2)
    @site.add_broken('http://example.com/c', 'http://e.com', :problem3)
    @site.blacklist 'http://b.com'
    @site.blacklist 'http://e.com'
    structure = @site.pages_by_blacklisted_link
    assert_equal 2, structure.length
    assert_kind_of Hash, structure
    assert_kind_of Array, structure['http://b.com']
    assert_includes structure['http://b.com'], 'http://example.com/a'
    assert_equal 1, structure['http://e.com'].length
    assert_equal 2, structure['http://b.com'].length
  end


  def test_orphan_blacklist_items_still_preserve_structure
    @site.add_broken('http://example.com/a', 'http://a.com', :problem1)
    @site.blacklist 'http://x.com'
    structure = @site.pages_by_blacklisted_link
    assert_kind_of Array, structure['http://x.com']
  end


  def test_add_to_temp_blacklist_adds_to_blacklist
    @site.add_broken('http://example.com/a', 'http://a.com', :problem1)
    @site.add_broken('http://example.com/a', 'http://b.com', :problem1)
    @site.temp_blacklist 'http://b.com'
    set = $redis.sdiff "#{$options.global_prefix}:#{@site.location}:page:http://example.com/a",
                       "#{$options.global_prefix}:#{@site.location}:blacklist:temp"
    refute_includes set, 'http://b.com'
  end


  def test_flush_temp_blacklist_flushes_temp_blacklist
    @site.add_broken('http://example.com/a', 'http://a.com', :problem1)
    @site.add_broken('http://example.com/a', 'http://b.com', :problem1)
    @site.temp_blacklist 'http://b.com'
    @site.flush_temp_blacklist
    set = $redis.sdiff "#{$options.global_prefix}:#{@site.location}:page:http://example.com/a",
                       "#{$options.global_prefix}:#{@site.location}:blacklist:temp"
    assert_includes set, 'http://b.com'
  end


  def test_flush_temp_blacklist_doesnt_flush_blacklist
    @site.add_broken('http://example.com/a', 'http://a.com', :problem1)
    @site.add_broken('http://example.com/a', 'http://b.com', :problem1)
    @site.blacklist 'http://b.com'
    @site.flush_temp_blacklist
    set = $redis.sdiff "#{$options.global_prefix}:#{@site.location}:page:http://example.com/a",
                       "#{$options.global_prefix}:#{@site.location}:blacklist"
    refute_includes set, 'http://b.com'
  end


  def test_remove_from_blacklist_removes_link_from_blacklist
    @site.add_broken('http://example.com/a', 'http://a.com', :problem1)
    @site.add_broken('http://example.com/a', 'http://b.com', :problem1)
    @site.blacklist 'http://b.com'
    @site.remove_from_blacklist 'http://b.com'
    set = $redis.sdiff "#{$options.global_prefix}:#{@site.location}:page:http://example.com/a",
                       "#{$options.global_prefix}:#{@site.location}:blacklist:temp"
    assert_includes set, 'http://b.com'
  end


  def test_counters_resetable
    @site.log_link 'http://a.com'
    @site.log_link 'http://b.com'
    @site.add_broken('http://example.com/a', 'http://a.com', :problem1)
    @site.log_page 'http://example.com/a'
    assert_equal '1', $redis.get("#{$options.global_prefix}:#{@site.location}:count:pages")
    assert_equal '2', $redis.get("#{$options.global_prefix}:#{@site.location}:count:checked")
    assert_equal '1', $redis.get("#{$options.global_prefix}:#{@site.location}:count:broken")
    @site.reset_counters
    assert_equal '0', $redis.get("#{$options.global_prefix}:#{@site.location}:count:pages")
    assert_equal '0', $redis.get("#{$options.global_prefix}:#{@site.location}:count:checked")
    assert_equal '0', $redis.get("#{$options.global_prefix}:#{@site.location}:count:broken")
  end


  def test_flush_issues_deletes_pages_and_problems
    @site.log_link 'http://a.com'
    @site.log_link 'http://b.com'
    @site.add_broken('http://example.com/a', 'http://a.com', :problem1)
    @site.log_page 'http://example.com/a'
    assert_includes $redis.smembers("#{$options.global_prefix}:#{@site.location}:pages"), 'http://example.com/a'
    assert_includes $redis.smembers("#{$options.global_prefix}:#{@site.location}:page:http://example.com/a"), 'http://a.com'
    assert_includes $redis.smembers("#{$options.global_prefix}:#{@site.location}:links"), 'http://a.com'
    assert_includes $redis.smembers("#{$options.global_prefix}:#{@site.location}:link:http://a.com"), 'http://example.com/a'
    assert_includes $redis.smembers("#{$options.global_prefix}:#{@site.location}:problems"), 'problem1'
    assert_includes $redis.smembers("#{$options.global_prefix}:#{@site.location}:problem:problem1"), 'http://a.com'
    @site.flush_issues
    assert_empty $redis.smembers("#{$options.global_prefix}:#{@site.location}:pages")
    assert_empty $redis.smembers("#{$options.global_prefix}:#{@site.location}:page:http://example.com/a")
    assert_empty $redis.smembers("#{$options.global_prefix}:#{@site.location}:links")
    assert_empty $redis.smembers("#{$options.global_prefix}:#{@site.location}:link:http://a.com")
    assert_empty $redis.smembers("#{$options.global_prefix}:#{@site.location}:problems")
    assert_empty $redis.smembers("#{$options.global_prefix}:#{@site.location}:problem:problem1")
  end


  def test_purge_orphaned_blacklist_removes_orphaned_blacklist_items_and_nothing_else
    @site.add_broken('http://example.com/a', 'http://a.com', :problem1)
    @site.add_broken('http://example.com/a', 'http://b.com', :problem1)
    @site.add_broken('http://example.com/a', 'http://c.com', :problem1)
    @site.blacklist 'http://a.com'
    @site.blacklist 'http://b.com'
    @site.blacklist 'http://c.com'

    structure = @site.pages_by_blacklisted_link
    assert_equal ['http://example.com/a'], structure['http://a.com']
    assert_equal ['http://example.com/a'], structure['http://b.com']
    assert_equal ['http://example.com/a'], structure['http://c.com']

    # simulating new crawl
    @site.reset_counters
    @site.flush_temp_blacklist
    @site.flush_issues

    assert_equal ['http://example.com/a'], structure['http://a.com']
    assert_equal ['http://example.com/a'], structure['http://b.com']
    assert_equal ['http://example.com/a'], structure['http://c.com']
    @site.add_broken('http://example.com/a', 'http://c.com', :problem1)

    # Purging
    Sites.purge_orphaned_blacklist_items

    structure = @site.pages_by_blacklisted_link

    assert_equal nil, structure['http://a.com']
    assert_equal nil, structure['http://b.com']

    assert_equal ['http://example.com/a'], structure['http://c.com']
  end


  def test_summary_report_string_generated
    csv = Sites.summary_report
    assert_kind_of String, csv
    assert_equal "Community,Pages,Checked,Broken\n", csv.to_a.first
  end


  def test_summary_report_only_reports_on_recent
    # Add a recently checked item
    $redis.sadd "#{$options.global_prefix}:sites", 'http://another.com'
    $redis.hset "#{$options.global_prefix}:http://another.com", 'location', 'http://another.com'
    $redis.hset "#{$options.global_prefix}:http://another.com", 'last_checked', Time.now.to_i
    csv = Sites.summary_report()
    assert_equal 2, csv.to_a.length
    # Add an non-recently checked item
    $redis.sadd "#{$options.global_prefix}:sites", 'http://defunct.com'
    $redis.hset "#{$options.global_prefix}:http://defunct.com", 'location', 'http://defunct.com'
    $redis.hset "#{$options.global_prefix}:http://defunct.com", 'last_checked', Time.at(0).to_i
    csv = Sites.summary_report()
    assert_equal 2, csv.to_a.length
    assert /another/ =~ csv.to_a[1]
    refute /defunct/ =~ csv.to_a[1]
  end
end
