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

  def test_cycles
    h = TSortHash[{1=>[2, 3], 2=>[1], 3=>[1]}]
    assert_equal([[1, 2], [1, 3]], h.cycles)

    h = TSortHash[{1=>[2, 3], 2=>[3], 3=>[]}]
    assert_equal([], h.cycles)
  end

  def test_each_cycle
    h = TSortHash[{1=>[2, 3], 2=>[1], 3=>[1]}]
    r = []
    h.each_cycle {|cycle| r << cycle }
    assert_equal([[1, 2], [1, 3]], r)

    enum = h.each_cycle
    assert_kind_of(Enumerator, enum)
    assert_equal([[1, 2], [1, 3]], enum.to_a)
  end

  def test_each_cycle_rotation_and_reversal
    # Cyclic shifts of a cycle are the same cycle.
    h = TSortHash[{1=>[2], 2=>[3], 3=>[1]}]
    assert_equal([[1, 2, 3]], h.cycles)

    # Reversed edges make a different cycle.
    h = TSortHash[{1=>[2, 3], 2=>[3], 3=>[1]}]
    assert_equal([[1, 2, 3], [1, 3]], h.cycles)
  end

  def test_each_cycle_self_loop
    h = TSortHash[{1=>[1], 2=>[]}]
    assert_equal([[1]], h.cycles)
  end

  def test_each_cycle_shared_node
    # Two cycles sharing a node but no edge must both be reported:
    # enumerating one must not block the other.
    h = TSortHash[{1=>[2], 2=>[3, 5], 3=>[4], 4=>[2], 5=>[6], 6=>[2]}]
    assert_equal([[2, 3, 4], [2, 5, 6]], h.cycles)
  end

  def test_each_cycle_lazy
    g = {1=>[2], 2=>[1], 3=>[4], 4=>[3]}
    each_node = lambda {|&b| g.each_key(&b) }
    called = 0
    each_child = lambda {|n, &b| called += 1; g[n].each(&b) }
    enum = TSort.each_cycle(each_node, each_child)
    assert_equal([[1, 2]], enum.first(1))
    assert_operator(called, :<, g.size)
  end

  def test_each_cycle_parallel_edges
    h = TSortHash[{1=>[2, 2], 2=>[1]}]
    assert_equal([[1, 2]], h.cycles)
    assert_equal([[1, 2]], h.cycles(unique_edges: true))
    assert_equal([[1, 2], [1, 2]], h.cycles(unique_edges: false))
  end

  def test_s_cycles
    g = {1=>[2, 3], 2=>[1], 3=>[1]}
    each_node = lambda {|&b| g.each_key(&b) }
    each_child = lambda {|n, &b| g[n].each(&b) }
    assert_equal([[1, 2], [1, 3]], TSort.cycles(each_node, each_child))

    r = []
    TSort.each_cycle(each_node, each_child) {|cycle| r << cycle }
    assert_equal([[1, 2], [1, 3]], r)

    r = TSort.each_cycle(each_node, each_child).map {|cycle|
      cycle.map(&:to_s)
    }
    assert_equal([['1', '2'], ['1', '3']], r)
  end
end
