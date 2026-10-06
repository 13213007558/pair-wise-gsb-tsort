# frozen_string_literal: true

require 'tsort'
require 'test/unit'

class TSortHash < Hash # :nodoc:
  include TSort
  alias tsort_each_node each_key
  def tsort_each_child(node, &block)
    fetch(node).each(&block)
  end
end

class TSortArray < Array # :nodoc:
  include TSort
  alias tsort_each_node each_index
  def tsort_each_child(node, &block)
    fetch(node).each(&block)
  end
end

class TSortTest < Test::Unit::TestCase # :nodoc:
  def test_dag
    h = TSortHash[{1=>[2, 3], 2=>[3], 3=>[]}]
    assert_equal([3, 2, 1], h.tsort)
    assert_equal([[3], [2], [1]], h.strongly_connected_components)
  end

  def test_cycle
    h = TSortHash[{1=>[2], 2=>[3, 4], 3=>[2], 4=>[]}]
    assert_equal([[4], [2, 3], [1]],
      h.strongly_connected_components.map {|nodes| nodes.sort})
    assert_raise(TSort::Cyclic) { h.tsort }
  end

  def test_array
    a = TSortArray[[1], [0], [0], [2]]
    assert_equal([[0, 1], [2], [3]],
      a.strongly_connected_components.map {|nodes| nodes.sort})

    a = TSortArray[[], [0]]
    assert_equal([[0], [1]],
      a.strongly_connected_components.map {|nodes| nodes.sort})
  end

  def test_s_tsort
    g = {1=>[2, 3], 2=>[4], 3=>[2, 4], 4=>[]}
    each_node = lambda {|&b| g.each_key(&b) }
    each_child = lambda {|n, &b| g[n].each(&b) }
    assert_equal([4, 2, 3, 1], TSort.tsort(each_node, each_child))
    g = {1=>[2], 2=>[3, 4], 3=>[2], 4=>[]}
    assert_raise(TSort::Cyclic) { TSort.tsort(each_node, each_child) }
  end

  def test_s_tsort_each
    g = {1=>[2, 3], 2=>[4], 3=>[2, 4], 4=>[]}
    each_node = lambda {|&b| g.each_key(&b) }
    each_child = lambda {|n, &b| g[n].each(&b) }
    r = []
    TSort.tsort_each(each_node, each_child) {|n| r << n }
    assert_equal([4, 2, 3, 1], r)

    r = TSort.tsort_each(each_node, each_child).map {|n| n.to_s }
    assert_equal(['4', '2', '3', '1'], r)
  end

  def test_s_strongly_connected_components
    g = {1=>[2, 3], 2=>[4], 3=>[2, 4], 4=>[]}
    each_node = lambda {|&b| g.each_key(&b) }
    each_child = lambda {|n, &b| g[n].each(&b) }
    assert_equal([[4], [2], [3], [1]],
                 TSort.strongly_connected_components(each_node, each_child))
    g = {1=>[2], 2=>[3, 4], 3=>[2], 4=>[]}
    assert_equal([[4], [2, 3], [1]],
                 TSort.strongly_connected_components(each_node, each_child))
  end

  def test_s_each_strongly_connected_component
    g = {1=>[2, 3], 2=>[4], 3=>[2, 4], 4=>[]}
    each_node = lambda {|&b| g.each_key(&b) }
    each_child = lambda {|n, &b| g[n].each(&b) }
    r = []
    TSort.each_strongly_connected_component(each_node, each_child) {|scc|
      r << scc
    }
    assert_equal([[4], [2], [3], [1]], r)
    g = {1=>[2], 2=>[3, 4], 3=>[2], 4=>[]}
    r = []
    TSort.each_strongly_connected_component(each_node, each_child) {|scc|
      r << scc
    }
    assert_equal([[4], [2, 3], [1]], r)

    r = TSort.each_strongly_connected_component(each_node, each_child).map {|scc|
      scc.map(&:to_s)
    }
    assert_equal([['4'], ['2', '3'], ['1']], r)
  end

  def test_s_each_strongly_connected_component_from
    g = {1=>[2], 2=>[3, 4], 3=>[2], 4=>[]}
    each_child = lambda {|n, &b| g[n].each(&b) }
    r = []
    TSort.each_strongly_connected_component_from(1, each_child) {|scc|
      r << scc
    }
    assert_equal([[4], [2, 3], [1]], r)

    r = TSort.each_strongly_connected_component_from(1, each_child).map {|scc|
      scc.map(&:to_s)
    }
    assert_equal([['4'], ['2', '3'], ['1']], r)
  end

  def test_linear_extension_count_chain
    # 1 -> 2 -> 3: the only valid execution order is [3, 2, 1].
    h = TSortHash[{1=>[2], 2=>[3], 3=>[]}]
    assert_equal(1, h.linear_extension_count)
  end

  def test_linear_extension_count_edgeless
    # No edges: every permutation is valid, 3! = 6.
    h = TSortHash[{1=>[], 2=>[], 3=>[]}]
    assert_equal(6, h.linear_extension_count)
  end

  def test_linear_extension_count_diamond
    # 1 -> 2 -> 4, 1 -> 3 -> 4: 4 first, 1 last, 2 and 3 in any order.
    h = TSortHash[{1=>[2, 3], 2=>[4], 3=>[4], 4=>[]}]
    assert_equal(2, h.linear_extension_count)
  end

  def test_linear_extension_count_bignum
    # Two disjoint chains of 40 nodes each: C(80, 40) extensions,
    # computed with only 41*41 subset states.
    g = {}
    1.upto(80) {|i| g[i] = (i % 40 == 0) ? [] : [i + 1] }
    h = TSortHash[g]
    expected = (41..80).reduce(1, :*) / (1..40).reduce(1, :*)
    assert_equal(expected, h.linear_extension_count)
    assert(expected > 2**64)
  end

  def test_linear_extension_count_cyclic
    h = TSortHash[{1=>[2], 2=>[1]}]
    assert_raise(TSort::Cyclic) { h.linear_extension_count }
  end

  def test_linear_extension_count_state_budget
    # 8 isolated nodes need 2**8 - 1 = 255 subset states.
    h = TSortHash[1.upto(8).map {|i| [i, []] }.to_h]
    assert_equal(40320, h.linear_extension_count(state_budget: 255))
    assert_raise(TSort::StateBudgetExceeded) {
      h.linear_extension_count(state_budget: 254)
    }
  end

  def test_linear_extension_rank_unrank_chain
    h = TSortHash[{1=>[2], 2=>[3], 3=>[]}]
    assert_equal(0, h.linear_extension_rank([3, 2, 1]))
    assert_equal([3, 2, 1], h.linear_extension_unrank(0))
    assert_raise(ArgumentError) { h.linear_extension_rank([1, 2, 3]) }
    assert_raise(ArgumentError) { h.linear_extension_unrank(1) }
  end

  def test_linear_extension_rank_unrank_edgeless
    # No edges: ranks follow lexicographic order of permutations,
    # numbered by node enumeration order [1, 2, 3].
    h = TSortHash[{1=>[], 2=>[], 3=>[]}]
    expected = [
      [1, 2, 3], [1, 3, 2], [2, 1, 3],
      [2, 3, 1], [3, 1, 2], [3, 2, 1],
    ]
    expected.each_with_index do |order, rank|
      assert_equal(order, h.linear_extension_unrank(rank))
      assert_equal(rank, h.linear_extension_rank(order))
    end
    assert_raise(ArgumentError) { h.linear_extension_unrank(6) }
    assert_raise(ArgumentError) { h.linear_extension_unrank(-1) }
    assert_raise(ArgumentError) { h.linear_extension_rank([1, 2, 4]) }
    assert_raise(ArgumentError) { h.linear_extension_rank([1, 2]) }
  end

  def test_linear_extension_rank_unrank_diamond
    h = TSortHash[{1=>[2, 3], 2=>[4], 3=>[4], 4=>[]}]
    assert_equal([4, 2, 3, 1], h.linear_extension_unrank(0))
    assert_equal([4, 3, 2, 1], h.linear_extension_unrank(1))
    assert_equal(0, h.linear_extension_rank([4, 2, 3, 1]))
    assert_equal(1, h.linear_extension_rank([4, 3, 2, 1]))
    assert_raise(ArgumentError) { h.linear_extension_rank([2, 4, 3, 1]) }
  end

  def test_linear_extension_sample
    # Diamond: exactly two valid orders, each must be samplable.
    h = TSortHash[{1=>[2, 3], 2=>[4], 3=>[4], 4=>[]}]
    random = Random.new(42)
    samples = 100.times.map { h.linear_extension_sample(random: random) }
    valid = [[4, 2, 3, 1], [4, 3, 2, 1]]
    samples.each {|s| assert_include(valid, s) }
    valid.each {|v| assert_include(samples, v) }
  end

  def test_linear_extension_sample_matches_unrank
    # Sampling must agree with unrank: the drawn number determines the
    # extension through the same ranking.
    h = TSortHash[{1=>[2, 3], 2=>[4], 3=>[4], 4=>[]}]
    fake = Object.new
    def fake.rand(n) n - 1 end
    assert_equal(h.linear_extension_unrank(1), h.linear_extension_sample(random: fake))
  end

  def test_linear_extension_sample_cyclic
    h = TSortHash[{1=>[2], 2=>[1]}]
    assert_raise(TSort::Cyclic) { h.linear_extension_sample }
  end

  def test_linear_extension_empty_graph
    h = TSortHash[{}]
    assert_equal(1, h.linear_extension_count)
    assert_equal([], h.linear_extension_unrank(0))
    assert_equal(0, h.linear_extension_rank([]))
    assert_equal([], h.linear_extension_sample)
  end

  def test_s_linear_extension
    g = {1=>[2, 3], 2=>[4], 3=>[4], 4=>[]}
    each_node = lambda {|&b| g.each_key(&b) }
    each_child = lambda {|n, &b| g[n].each(&b) }
    assert_equal(2, TSort.linear_extension_count(each_node, each_child))
    assert_equal([4, 3, 2, 1], TSort.linear_extension_unrank(1, each_node, each_child))
    assert_equal(1, TSort.linear_extension_rank([4, 3, 2, 1], each_node, each_child))
    sample = TSort.linear_extension_sample(each_node, each_child, random: Random.new(7))
    assert_include([[4, 2, 3, 1], [4, 3, 2, 1]], sample)
  end
end
