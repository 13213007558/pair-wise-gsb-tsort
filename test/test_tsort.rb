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

  def test_minimum_chain_cover_empty_graph
    graph = TSortHash[{}]

    result = graph.minimum_chain_cover

    assert_equal([], result[:chains])
    assert_equal([], result[:maximum_antichain])
  end

  def test_minimum_chain_cover_isolated_nodes
    graph = TSortHash[{1=>[], 2=>[], 3=>[]}]

    result = graph.minimum_chain_cover

    assert_equal(3, result[:chains].length)
    assert_equal([[1], [2], [3]], result[:chains].map {|chain| chain[:nodes] })
    assert_equal([[], [], []], result[:chains].map {|chain| chain[:paths] })
    assert_equal([1, 2, 3], result[:maximum_antichain].sort)
    assert_chain_cover(graph, result)
  end

  def test_minimum_chain_cover_uses_indirect_paths
    graph = TSortHash[{
      1=>[3],
      2=>[3],
      3=>[4, 5],
      4=>[],
      5=>[]
    }]

    result = graph.minimum_chain_cover

    indirect_chain = result[:chains].find {|chain|
      chain[:paths].any? {|path| path == [2, 3, 5] || path == [1, 3, 4] || path == [2, 3, 4] || path == [1, 3, 5] }
    }
    assert_not_nil(indirect_chain)
    assert_equal(2, result[:maximum_antichain].length)
    assert_chain_cover(graph, result)
  end

  def test_minimum_chain_cover_maximum_antichain_across_topological_levels
    graph = TSortHash[{
      1=>[2, 5],
      2=>[3, 4],
      3=>[],
      4=>[6],
      5=>[6, 7],
      6=>[],
      7=>[8],
      8=>[]
    }]
    levels = {
      1=>0,
      2=>1, 5=>1,
      3=>2, 4=>2, 6=>2, 7=>2,
      8=>3
    }

    result = graph.minimum_chain_cover

    assert_equal(3, result[:chains].length)
    assert_equal([3, 6, 8], result[:maximum_antichain].sort)
    assert_equal(2, result[:maximum_antichain].map {|node| levels[node] }.uniq.length)
    assert_chain_cover(graph, result)
  end

  def test_s_minimum_chain_cover
    graph = {
      1=>[2],
      2=>[],
      3=>[],
      'a'=>['b'],
      'b'=>[]
    }
    each_node = lambda {|&b| graph.each_key(&b) }
    each_child = lambda {|n, &b| graph[n].each(&b) }

    result = TSort.minimum_chain_cover(each_node, each_child)

    assert_equal(3, result[:chains].length)
    assert_chain_cover(graph, result)
  end

  def test_minimum_chain_cover_cycle
    graph = TSortHash[{1=>[2], 2=>[1]}]

    assert_raise(TSort::Cyclic) { graph.minimum_chain_cover }
  end

  private

  def assert_chain_cover(graph, result)
    nodes = graph.keys.sort_by(&:inspect)
    chain_nodes = result[:chains].flat_map {|chain| chain[:nodes] }

    assert_equal(nodes, chain_nodes.sort_by(&:inspect))
    assert_equal(chain_nodes.length, chain_nodes.uniq.length)

    result[:chains].each {|chain|
      chain_nodes = chain[:nodes]
      assert_equal(chain_nodes.length - 1, chain[:paths].length)
      chain_nodes.each_cons(2).with_index {|(source, target), index|
        path = chain[:paths][index]
        assert_equal(source, path.first)
        assert_equal(target, path.last)
        path.each_cons(2) {|from, to|
          assert(graph[from].include?(to))
        }
      }
    }

    antichain = result[:maximum_antichain]
    antichain.each {|node|
      (antichain - [node]).each {|other|
        refute(reachable?(graph, node, other) ||
               reachable?(graph, other, node))
      }
    }
    assert_equal(result[:chains].length, antichain.length)
  end

  def reachable?(graph, source, target)
    visited = {}
    queue = [source]

    until queue.empty?
      node = queue.shift
      return true if node == target
      next if visited.key?(node)
      visited[node] = true
      queue.concat(graph[node])
    end

    false
  end
end
