# frozen_string_literal: true

require 'tsort'
require 'test/unit'

class NetworkReliabilityTest < Test::Unit::TestCase
  def test_shared_bridge_counts_edge_once
    edges = [
      [:s, :a],
      [:s, :b],
      [:a, :b],
      [:a, :t],
      [:b, :t]
    ]
    reliability = TSort::NetworkReliability.new(edges, :s, :t)

    assert_equal([0, 0, 2, 1, -3, 1], reliability.polynomial)
    assert_equal(Rational(15, 32), reliability.probability(Rational(1, 2)))
    assert_in_delta(0.46875, reliability.value_at(0.5))
    assert_operator(reliability.state_count, :<, 2 ** edges.length)
  end

  def test_common_path_bridge
    edges = [
      [:s, :a],
      [:s, :b],
      [:a, :m],
      [:b, :m],
      [:m, :t]
    ]
    reliability = TSort::NetworkReliability.new(edges, :s, :t)

    assert_equal([0, 0, 0, 2, 0, -1], reliability.polynomial)
    assert_equal(Rational(7, 32), reliability.probability(Rational(1, 2)))
  end

  def test_parallel_edges_are_independent
    edges = [[:s, :t], [:s, :t]]
    reliability = TSort::NetworkReliability.new(edges, :s, :t)

    assert_equal([0, 2, -1], reliability.polynomial)
    assert_equal(0.0, reliability.value_at(0))
    assert_equal(1.0, reliability.value_at(1))
    assert_equal(0.75, reliability.probability(0.5))
    assert_in_delta(0.88, reliability.probability([0.6, 0.7]))
  end

  def test_zero_one_and_disconnected_graph
    series = TSort::NetworkReliability.new(
      [[:s, :a], [:a, :t]], :s, :t
    )

    assert_equal([0, 0, 1], series.polynomial)
    assert_equal(0, series.probability(0))
    assert_equal(1, series.probability(1))
    assert_equal(0.0, series.value_at(0))
    assert_equal(1.0, series.value_at(1))

    disconnected = TSort::NetworkReliability.new(
      [[:s, :a], [:other, :t]], :s, :t
    )

    assert_equal([0], disconnected.polynomial)
    assert_equal(0, disconnected.probability(1))
    assert_equal(0, disconnected.state_count)
  end

  def test_source_equal_target
    reliability = TSort::NetworkReliability.new(
      [[:s, :a], [:s, :s]], :s, :s
    )

    assert_equal([1], reliability.polynomial)
    assert_equal(1, reliability.probability(0))
    assert_equal(0, reliability.state_count)
  end

  def test_directed_cycle
    edges = [[:s, :a], [:a, :b], [:b, :a], [:a, :t]]
    reliability = TSort::NetworkReliability.new(edges, :s, :t)

    assert_equal([0, 0, 1], reliability.polynomial)
    assert_equal(Rational(1, 4), reliability.probability(Rational(1, 2)))
    assert_operator(reliability.state_count, :<, 2 ** edges.length)
  end

  def test_independent_edge_probabilities_match_enumeration
    edges = [
      [:s, :a],
      [:s, :b],
      [:a, :b],
      [:a, :t],
      [:b, :t],
      [:a, :dead]
    ]
    probabilities = [
      Rational(1, 2),
      Rational(1, 3),
      Rational(1, 5),
      Rational(1, 7),
      Rational(1, 11),
      Rational(1, 13)
    ]
    reliability = TSort::NetworkReliability.new(edges, :s, :t)

    assert_equal(
      enumerate_reliability(edges, :s, :t, probabilities),
      reliability.probability(probabilities)
    )
    assert_operator(reliability.state_count, :<, 2 ** edges.length)
  end

  def test_probabilities_can_be_carried_by_edges
    edges = [[:s, :t, 0.25], [:s, :t, 0.5]]

    assert_in_delta(
      0.625,
      TSort::NetworkReliability.probability(edges, :s, :t)
    )
  end

  private

  def enumerate_reliability(edges, source, target, probabilities)
    (0...(1 << edges.length)).inject(0) do |total, mask|
      adjacency = Hash.new {|hash, key| hash[key] = []}
      probability = 1

      edges.each_with_index do |edge, index|
        edge_p = probabilities.fetch(index)
        if mask[index].nonzero?
          adjacency[edge[0]] << edge[1]
          probability *= edge_p
        else
          probability *= 1 - edge_p
        end
      end

      total + (connected?(adjacency, source, target) ? probability : 0)
    end
  end

  def connected?(adjacency, source, target)
    seen = {source => true}
    stack = [source]
    until stack.empty?
      node = stack.pop
      return true if node == target

      adjacency[node].each do |child|
        next if seen[child]
        seen[child] = true
        stack << child
      end
    end
    false
  end
end
