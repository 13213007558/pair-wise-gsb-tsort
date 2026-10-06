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
end

class TSortLinearExtensionTest < Test::Unit::TestCase # :nodoc:
  def test_chain_count
    # 1 depends on 2, 2 depends on 3: only one legal execution order.
    h = TSortHash[{1=>[2], 2=>[3], 3=>[]}]
    assert_equal(1, h.linear_extension_count)
  end

  def test_chain_unrank_and_rank
    h = TSortHash[{1=>[2], 2=>[3], 3=>[]}]
    assert_equal([3, 2, 1], h.linear_extension_unrank(0))
    assert_equal(0, h.linear_extension_rank([3, 2, 1]))
    assert_raise(ArgumentError) { h.linear_extension_unrank(1) }
    assert_raise(ArgumentError) { h.linear_extension_unrank(-1) }
    assert_raise(ArgumentError) { h.linear_extension_rank([2, 3, 1]) }
    assert_raise(ArgumentError) { h.linear_extension_rank([3, 2]) }
    assert_raise(ArgumentError) { h.linear_extension_rank([3, 2, 1, 1]) }
  end

  def test_edgeless_count
    # No edges: every permutation is legal, 3! = 6 orders.
    h = TSortHash[{1=>[], 2=>[], 3=>[]}]
    assert_equal(6, h.linear_extension_count)
  end

  def test_edgeless_unrank_is_lexicographic
    h = TSortHash[{1=>[], 2=>[], 3=>[]}]
    expected = [
      [1, 2, 3], [1, 3, 2], [2, 1, 3],
      [2, 3, 1], [3, 1, 2], [3, 2, 1],
    ]
    assert_equal(expected, (0...6).map {|r| h.linear_extension_unrank(r) })
    expected.each_with_index do |order, r|
      assert_equal(r, h.linear_extension_rank(order))
    end
  end

  def test_diamond
    # 4 must run first, 1 must run last, 2 and 3 in either order.
    h = TSortHash[{1=>[2, 3], 2=>[4], 3=>[4], 4=>[]}]
    assert_equal(2, h.linear_extension_count)
    assert_equal([4, 2, 3, 1], h.linear_extension_unrank(0))
    assert_equal([4, 3, 2, 1], h.linear_extension_unrank(1))
    assert_equal(0, h.linear_extension_rank([4, 2, 3, 1]))
    assert_equal(1, h.linear_extension_rank([4, 3, 2, 1]))
    assert_raise(ArgumentError) { h.linear_extension_unrank(2) }
    assert_raise(ArgumentError) { h.linear_extension_rank([2, 4, 3, 1]) }
  end

  def test_rank_unrank_roundtrip_against_brute_force
    h = TSortHash[{1=>[3], 2=>[3], 3=>[4, 5], 4=>[], 5=>[]}]
    # 4 and 5 first (2 orders), then 3, then 1 and 2 (2 orders): 4 total.
    count = h.linear_extension_count
    assert_equal(4, count)
    nodes = [1, 2, 3, 4, 5]
    brute = nodes.permutation.select do |perm|
      pos = {}
      perm.each_with_index {|n, i| pos[n] = i }
      h.all? {|node, children|
        children.all? {|child| pos[child] < pos[node] }
      }
    end
    assert_equal(count, brute.size)
    unranked = (0...count).map {|r| h.linear_extension_unrank(r) }
    assert_equal(brute.sort, unranked.sort)
    unranked.each_with_index do |order, r|
      assert_equal(r, h.linear_extension_rank(order))
    end
  end

  def test_tsort_result_is_a_rankable_extension
    h = TSortHash[{1=>[2, 3], 2=>[4], 3=>[4], 4=>[]}]
    order = h.tsort
    rank = h.linear_extension_rank(order)
    assert_operator(rank, :>=, 0)
    assert_operator(rank, :<, h.linear_extension_count)
    assert_equal(order, h.linear_extension_unrank(rank))
  end

  def test_count_uses_bignum
    # Three disjoint chains of 25 nodes: 75!/(25!)^3 extensions,
    # a value far beyond 64 bits, computed exactly.
    g = {}
    3.times do |c|
      chain = (1..25).map {|i| "#{c}-#{i}" }
      chain.each_cons(2) {|a, b| g[a] = [b] }
      g[chain.last] = []
    end
    h = TSortHash[g]
    expected = (1..75).reduce(1, :*) / (1..25).reduce(1, :*)**3
    assert_operator(expected, :>, 2**112)
    assert_equal(expected, h.linear_extension_count)
  end

  def test_state_budget_exceeded
    # Edgeless graph on 10 nodes visits 2**10 = 1024 subset states.
    h = TSortHash[(1..10).map {|i| [i, []] }.to_h]
    assert_raise(TSort::StateBudgetExceeded) {
      h.linear_extension_count(max_states: 100)
    }
    assert_equal((1..10).reduce(1, :*), h.linear_extension_count(max_states: 2000))
  end

  def test_cyclic
    h = TSortHash[{1=>[2], 2=>[1]}]
    assert_raise(TSort::Cyclic) { h.linear_extension_count }
    assert_raise(TSort::Cyclic) { h.linear_extension_unrank(0) }
    assert_raise(TSort::Cyclic) { h.linear_extension_sample }
  end

  def test_empty_graph
    h = TSortHash[]
    assert_equal(1, h.linear_extension_count)
    assert_equal([], h.linear_extension_unrank(0))
    assert_equal(0, h.linear_extension_rank([]))
    assert_equal([], h.linear_extension_sample)
  end

  def test_sample_uses_exact_uniform_rank
    h = TSortHash[{1=>[2, 3], 2=>[4], 3=>[4], 4=>[]}]
    first = Object.new
    def first.rand(n) 0 end
    assert_equal([4, 2, 3, 1], h.linear_extension_sample(random: first))
    last = Object.new
    def last.rand(n) n - 1 end
    assert_equal([4, 3, 2, 1], h.linear_extension_sample(random: last))
  end

  def test_sample_covers_all_extensions
    h = TSortHash[{1=>[2, 3], 2=>[4], 3=>[4], 4=>[]}]
    random = Random.new(42)
    seen = {}
    100.times do
      seen[h.linear_extension_sample(random: random)] = true
    end
    assert_equal([[4, 2, 3, 1], [4, 3, 2, 1]].sort, seen.keys.sort)
  end

  def test_s_linear_extension
    g = {1=>[2, 3], 2=>[4], 3=>[4], 4=>[]}
    each_node = lambda {|&b| g.each_key(&b) }
    each_child = lambda {|n, &b| g[n].each(&b) }
    assert_equal(2, TSort.linear_extension_count(each_node, each_child))
    assert_equal([4, 2, 3, 1], TSort.linear_extension_unrank(each_node, each_child, 0))
    assert_equal([4, 3, 2, 1], TSort.linear_extension_unrank(each_node, each_child, 1))
    assert_equal(0, TSort.linear_extension_rank(each_node, each_child, [4, 2, 3, 1]))
    assert_equal(1, TSort.linear_extension_rank(each_node, each_child, [4, 3, 2, 1]))
    order = TSort.linear_extension_sample(each_node, each_child, random: Random.new(7))
    assert_include([[4, 2, 3, 1], [4, 3, 2, 1]], order)
    assert_raise(TSort::StateBudgetExceeded) {
      TSort.linear_extension_count(each_node, each_child, max_states: 1)
    }
  end
end
