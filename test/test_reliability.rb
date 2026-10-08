# frozen_string_literal: true

require 'tsort'
require 'test/unit'

class ReliabilityTest < Test::Unit::TestCase # :nodoc:
  # Reference implementation: enumerates all 2**E edge subsets.
  def brute_force(edges, source, sink, probs)
    total = 0.0
    (0...(1 << edges.size)).each do |mask|
      adj = Hash.new { |h, k| h[k] = [] }
      weight = 1.0
      edges.each_with_index do |(u, v), i|
        if mask[i] == 1
          adj[u] << v
          weight *= probs[i]
        else
          weight *= (1 - probs[i])
        end
      end
      seen = { source => true }
      queue = [source]
      until queue.empty?
        x = queue.shift
        adj[x].each do |y|
          unless seen[y]
            seen[y] = true
            queue << y
          end
        end
      end
      total += weight if seen[sink]
    end
    total
  end

  # Two edge-disjoint routes sharing the single bridge :x -> :t.
  SHARED_BRIDGE = [[:s, :a], [:s, :b], [:a, :x], [:b, :x], [:x, :t]].freeze

  def test_shared_bridge_polynomial
    rel = TSort::Reliability.new(SHARED_BRIDGE)
    # p * (1 - (1 - p**2)**2) == 2*p**3 - p**5
    assert_equal([0, 0, 0, 2, 0, -1], rel.polynomial(:s, :t))
  end

  def test_shared_bridge_numeric_matches_brute_force
    rel = TSort::Reliability.new(SHARED_BRIDGE)
    probs = [0.9, 0.8, 0.7, 0.6, 0.5]
    assert_in_delta(brute_force(SHARED_BRIDGE, :s, :t, probs),
                    rel.probability(:s, :t, probs), 1e-12)
  end

  def test_parallel_edges_are_merged
    rel = TSort::Reliability.new([[:s, :t], [:s, :t]])
    # 1 - (1-p)**2 == 2*p - p**2
    assert_equal([0, 2, -1], rel.polynomial(:s, :t))
    assert_equal(1, rel.state_count(:s, :t))
    assert_in_delta(0.75, rel.probability(:s, :t, [0.5, 0.5]))
    assert_in_delta(1 - 0.7 * 0.2, rel.probability(:s, :t, [0.3, 0.8]))
  end

  def test_p_zero_and_p_one
    rel = TSort::Reliability.new([[:s, :a], [:a, :t]])
    assert_equal(0, rel.probability(:s, :t, [0.0, 0.0]))
    assert_equal(1, rel.probability(:s, :t, [1.0, 1.0]))
    disconnected = TSort::Reliability.new([[:s, :a], [:b, :t]])
    assert_equal(0, disconnected.probability(:s, :t, [1.0, 1.0]))
    assert_equal([0], disconnected.polynomial(:s, :t))
  end

  def test_same_source_and_sink
    rel = TSort::Reliability.new([[:s, :a]])
    assert_equal(1, rel.probability(:s, :s, [0.5]))
    assert_equal([1], rel.polynomial(:s, :s))
    assert_equal(0, rel.state_count(:s, :s))
  end

  def test_directed_edges_are_not_contracted_like_undirected
    # Undirected-style edge contraction would merge :u and :v when
    # :u -> :v survives and wrongly report :s reaches :t.
    edges = [[:s, :v], [:u, :t], [:u, :v]]
    rel = TSort::Reliability.new(edges)
    assert_equal(0, rel.probability(:s, :t, [1.0, 1.0, 1.0]))
    assert_equal([0], rel.polynomial(:s, :t))
  end

  def test_self_loops_are_ignored
    rel = TSort::Reliability.new([[:s, :s], [:s, :t]])
    assert_equal([0, 1], rel.polynomial(:s, :t))
    assert_in_delta(0.3, rel.probability(:s, :t, [0.9, 0.3]))
  end

  def test_against_exhaustive_enumeration
    graphs = [
      SHARED_BRIDGE + [[:s, :t]],
      [[:s, :a], [:a, :b], [:b, :a], [:b, :t], [:s, :b]],
      [[:s, :a], [:s, :b], [:a, :b], [:a, :t], [:b, :t], [:s, :a]],
      [[:s, :t], [:s, :t], [:s, :a], [:a, :t]],
      [[:s, :s], [:s, :a], [:a, :t], [:t, :t]],
    ]
    graphs.each_with_index do |edges, g|
      probs = edges.each_index.map { |i| 0.15 + 0.1 * (i % 7) }
      rel = TSort::Reliability.new(edges)
      assert_in_delta(brute_force(edges, :s, :t, probs),
                      rel.probability(:s, :t, probs),
                      1e-9, "graph #{g}: numeric probability")

      poly = rel.polynomial(:s, :t)
      assert(poly.all? { |c| c.is_a?(Integer) },
             "graph #{g}: coefficients must be integers")
      [0.0, 0.2, 0.5, 0.9, 1.0].each do |p|
        expected = brute_force(edges, :s, :t, [p] * edges.size)
        actual = TSort::Reliability.evaluate_polynomial(poly, p)
        assert_in_delta(expected, actual, 1e-9,
                        "graph #{g}: polynomial at p=#{p}")
      end

      assert_operator(rel.state_count(:s, :t), :<, 2**edges.size,
                      "graph #{g}: diagram must share states")
    end
  end

  def test_state_count_grows_slower_than_enumeration
    layer1 = [:a, :b, :c]
    layer2 = [:d, :e, :f]
    edges = layer1.map { |u| [:s, u] } +
            layer1.product(layer2).map { |u, v| [u, v] } +
            layer2.map { |v| [v, :t] }
    rel = TSort::Reliability.new(edges)
    assert_equal(15, edges.size)
    assert_operator(rel.state_count(:s, :t), :<, 1000)
    assert_equal(1, rel.probability(:s, :t, [1.0] * edges.size))
    assert_equal(0, rel.probability(:s, :t, [0.0] * edges.size))
  end

  def test_probability_argument_validation
    rel = TSort::Reliability.new([[:s, :t]])
    assert_raise(ArgumentError) { rel.probability(:s, :t, []) }
    assert_raise(ArgumentError) { rel.probability(:s, :t, [0.5, 0.5]) }
  end

  def test_unknown_endpoints
    rel = TSort::Reliability.new([[:s, :t]])
    assert_equal(0, rel.probability(:s, :nowhere, [0.5]))
    assert_equal(0, rel.probability(:nowhere, :t, [0.5]))
    assert_equal([0], rel.polynomial(:s, :nowhere))
    assert_equal(0, rel.state_count(:s, :nowhere))
  end
end
