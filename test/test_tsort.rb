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

  def test_minimum_chain_cover_empty
    graph = TSortHash.new
    result = graph.minimum_chain_cover

    assert_equal([], result[:chains])
    assert_equal([], result[:antichain])
    assert_equal(0, result[:size])
  end

  def test_minimum_chain_cover_isolated_nodes
    graph = TSortHash[{1=>[], 2=>[], 3=>[]}]
    result = graph.minimum_chain_cover

    assert_equal([
      {nodes: [1], paths: []},
      {nodes: [2], paths: []},
      {nodes: [3], paths: []}
    ], result[:chains])
    assert_equal([1, 2, 3], result[:antichain])
    assert_equal(3, result[:size])
  end

  def test_minimum_chain_cover_indirect_paths
    graph = TSortHash[{
      1=>[3],
      2=>[3],
      3=>[4, 5],
      4=>[],
      5=>[]
    }]
    result = graph.minimum_chain_cover

    assert_equal(2, result[:size])
    assert_equal(result[:size], result[:chains].length)
    assert_equal(result[:size], result[:antichain].length)
    assert_equal([1, 2, 3, 4, 5], result[:chains].flat_map {|chain| chain[:nodes]}.sort)

    indirect_chain = result[:chains].find {|chain| chain[:paths].any? {|path| path.length > 2}}
    assert(indirect_chain)
    witness_nodes = indirect_chain[:paths].flat_map {|path| path[1...-1]}
    assert(witness_nodes.any? {|node| !indirect_chain[:nodes].include?(node)})

    result[:chains].each do |chain|
      assert_equal(chain[:nodes].length - 1, chain[:paths].length)
      chain[:nodes].each_cons(2).with_index do |(child, parent), index|
        path = chain[:paths][index]
        assert_equal([child, parent], path.values_at(0, -1))
        assert(path.each_cons(2).all? {|a, b| graph[b].include?(a)})
      end
    end

    result[:antichain].combination(2) do |a, b|
      assert_equal(false, comparable?(graph, a, b))
    end
  end

  def test_minimum_chain_cover_antichain_across_topological_layers
    graph = TSortHash[{
      :a=>[:b],
      :b=>[:c1, :c2],
      :c1=>[:d1],
      :c2=>[:d1],
      :d1=>[],
      :x=>[:y],
      :y=>[]
    }]
    result = graph.minimum_chain_cover
    topo = graph.tsort
    layers = topological_layers(graph, topo)
    antichain_layers = result[:antichain].map {|node| layers.fetch(node)}.uniq

    assert_equal(3, result[:size])
    assert_equal(3, result[:antichain].length)
    assert_equal([0, 1], antichain_layers.sort)
    assert_equal(graph.keys.sort, result[:chains].flat_map {|chain| chain[:nodes]}.sort)
  end

  def test_s_minimum_chain_cover
    g = {1=>[2, 3], 2=>[3], 3=>[]}
    each_node = lambda {|&b| g.each_key(&b) }
    each_child = lambda {|n, &b| g[n].each(&b) }
    result = TSort.minimum_chain_cover(each_node, each_child)

    assert_equal([
      {nodes: [3, 2, 1], paths: [[3, 2], [2, 1]]}
    ], result[:chains])
    assert_equal([3], result[:antichain])
    assert_equal(1, result[:size])
  end

  def test_minimum_chain_cover_cycle
    graph = TSortHash[{1=>[2], 2=>[3], 3=>[1]}]
    assert_raise(TSort::Cyclic) { graph.minimum_chain_cover }
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

  private

  def comparable?(graph, a, b)
    reachable?(graph, a, b) || reachable?(graph, b, a)
  end

  def reachable?(graph, source, target)
    pending = [source]
    visited = {source => true}

    until pending.empty?
      node = pending.shift
      return true if node == target
      graph[node].each do |child|
        unless visited.include?(child)
          visited[child] = true
          pending << child
        end
      end
    end
    false
  end

  def topological_layers(graph, topo)
    layers = {}
    topo.each do |node|
      layers[node] = graph[node].map {|child| layers.fetch(child) + 1}.max || 0
    end
    layers
  end
end
