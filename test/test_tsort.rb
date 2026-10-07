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

class IdentityEdgeGraph # :nodoc:
  include TSort

  def initialize(nodes, edges)
    @nodes = nodes
    @edges = edges
  end

  def tsort_each_node(&block)
    @nodes.each(&block)
  end

  def tsort_each_edge(node, &block)
    @edges.each do |edge|
      yield edge if edge.source == node
    end
  end
end

def edge(source, target, id)
  TSort::DirectedEdge.new(source, target, id)
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

  def test_series_parallel_decomposition_from_generated_positive_graph
    seed =
      TSort::Decomposition::Parallel.build(:s, :t, [
        TSort::Decomposition::Series.build(:s, :t, [
          TSort::Decomposition::Edge.new(:s, :a, :sa, uid: nil),
          TSort::Decomposition::Edge.new(:a, :t, :at, uid: nil)
        ], uid: nil),
        TSort::Decomposition::Series.build(:s, :t, [
          TSort::Decomposition::Edge.new(:s, :b, :sb, uid: nil),
          TSort::Decomposition::Edge.new(:b, :t, :bt, uid: nil)
        ], uid: nil)
      ], uid: nil)

    generated = seed.expand
    assert_equal(seed.each_node.to_a, seed.each_node.to_a.uniq)
    input = TSort::Graph.new(
      generated.nodes,
      generated.edges.map {|edge|
        TSort::DirectedEdge.new(edge.source, edge.target, edge.id)
      })
    assert_equal([:sa, :at, :sb, :bt], generated.edges.map(&:id))
    result = input.series_parallel_decomposition(:s, :t)

    assert_equal(true, result.ok?)
    assert_equal([:sa, :at, :sb, :bt],
                 result.tree.original_edge_ids)
    assert_equal([:s, :t], result.residual_graph.nodes)
    assert_equal(1, result.residual_edges.size)
    assert_equal(true, result.verified?)
    assert_equal(result.residual_graph.nodes, result.replay.nodes)
    assert_equal(result.residual_edges.map(&:uid),
                 result.replay.edges.map(&:uid))
  end

  def test_series_parallel_cross_edge_returns_replayable_residual
    nodes = [:s, :a, :b, :t]
    edges = [
      edge(:s, :a, :sa),
      edge(:s, :b, :sb),
      edge(:a, :t, :at),
      edge(:b, :t, :bt)
    ]
    seed = IdentityEdgeGraph.new(nodes, edges).
      series_parallel_decomposition(:s, :t).tree
    generated_edges = seed.expand.edges.map do |generated_edge|
      edge(generated_edge.source, generated_edge.target, generated_edge.id)
    end
    edges = generated_edges + [edge(:a, :b, :cross)]
    result = IdentityEdgeGraph.new(nodes, edges).
      series_parallel_decomposition(:s, :t)

    assert_equal(false, result.ok?)
    assert_nil(result.tree)
    assert_equal(nodes, result.residual_graph.all_nodes)
    assert_equal(nodes, result.residual_graph.nodes)
    assert_equal(5, result.residual_edges.size)
    assert_equal([:reduction_stuck],
                 result.diagnostics.map(&:code))
    assert_equal(true, result.verified?)
  end

  def test_series_parallel_rejects_duplicate_explicit_edge_identities
    nodes = [:s, :t]
    edges = [
      edge(:s, :t, :same),
      edge(:s, :t, :same)
    ]
    result = IdentityEdgeGraph.new(nodes, edges).
      series_parallel_decomposition(:s, :t)

    assert_equal(false, result.ok?)
    assert_equal([:duplicate_edge_identity, :duplicate_edge_identity],
                 result.diagnostics.map(&:code))
    assert_equal(2, result.residual_edges.size)
    assert_equal(true, result.verified?)
  end

  def test_series_parallel_keeps_parallel_edge_identities
    nodes = [:s, :t]
    edges = [
      edge(:s, :t, :first),
      edge(:s, :t, :second)
    ]
    result = IdentityEdgeGraph.new(nodes, edges).
      series_parallel_decomposition(:s, :t)

    assert_equal(true, result.ok?)
    assert_instance_of(TSort::Decomposition::Parallel, result.tree)
    assert_equal([:first, :second], result.tree.original_edge_ids)
    assert_equal(true, result.verified?)
  end

  def test_series_parallel_synthetic_child_edges_also_remain_parallel
    graph = TSortHash[{:s => [:t, :t], :t => []}]
    result = graph.series_parallel_decomposition(:s, :t)

    assert_equal(true, result.ok?)
    assert_instance_of(TSort::Decomposition::Parallel, result.tree)
    assert_equal(2, result.tree.original_edge_ids.size)
    assert_equal(true, result.verified?)
  end

  def test_series_parallel_reports_isolated_node
    nodes = [:s, :t, :x]
    result = IdentityEdgeGraph.new(nodes, [edge(:s, :t, :st)]).
      series_parallel_decomposition(:s, :t)

    assert_equal(false, result.ok?)
    assert_equal([:isolated_node], result.diagnostics.map(&:code))
    assert_equal(nodes, result.residual_graph.all_nodes)
    assert_equal(nodes, result.residual_graph.nodes)
    assert_equal([:st], result.residual_edges.map(&:id))
    assert_equal(true, result.verified?)
  end

  def test_series_parallel_reports_component_off_source_sink_path
    nodes = [:s, :t, :a, :b]
    edges = [
      edge(:s, :t, :st),
      edge(:a, :b, :ab)
    ]
    result = IdentityEdgeGraph.new(nodes, edges).
      series_parallel_decomposition(:s, :t)

    assert_equal(false, result.ok?)
    assert_include(result.diagnostics.map(&:code),
                   :node_not_reachable_from_source)
    assert_include(result.diagnostics.map(&:code),
                   :node_cannot_reach_sink)
    assert_include(result.diagnostics.map(&:code),
                   :edge_not_on_source_sink_path)
    assert_equal(nodes, result.residual_graph.nodes)
    assert_equal([:st, :ab], result.residual_edges.map(&:id))
    assert_equal(true, result.verified?)
  end

  def test_series_parallel_reports_back_edge
    nodes = [:s, :t]
    edges = [
      edge(:s, :t, :forward),
      edge(:t, :s, :back)
    ]
    result = IdentityEdgeGraph.new(nodes, edges).
      series_parallel_decomposition(:s, :t)

    assert_equal(false, result.ok?)
    assert_include(result.diagnostics.map(&:code), :cyclic_edge)
    assert_equal([:back, :forward],
                 result.residual_edges.map(&:id).sort)
    assert_equal(true, result.verified?)
  end

  def test_series_parallel_reports_self_loop
    nodes = [:s, :a, :t]
    edges = [
      edge(:s, :a, :sa),
      edge(:a, :a, :self),
      edge(:a, :t, :at)
    ]
    result = IdentityEdgeGraph.new(nodes, edges).
      series_parallel_decomposition(:s, :t)

    assert_equal(false, result.ok?)
    assert_include(result.diagnostics.map(&:code), :cyclic_edge)
    assert_equal(nodes, result.residual_graph.nodes)
    assert_include(result.residual_edges.map(&:id), :self)
    assert_equal(true, result.verified?)
  end
end
