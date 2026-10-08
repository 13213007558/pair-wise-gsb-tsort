# frozen_string_literal: true

module TSort
  class NetworkReliability
    State = Struct.new(:edge, :dead, :alive) # :nodoc:

    def initialize(edges, source, target, probabilities = nil)
      @source = source
      @target = target
      @probabilities = probabilities
      setup_edges(edges.to_a)
    end

    # Returns the terminal-to-terminal reliability using independently
    # assigned edge probabilities.
    #
    # +probabilities+ may be a Numeric, an array aligned with the edges, or a
    # callable receiving an edge and returning its probability. When omitted,
    # an edge may carry its probability as a third element.
    def probability(probabilities = @probabilities)
      build
      evaluate_numeric(@root, probabilities)
    end

    # Evaluates the common-variable reliability polynomial at +p+.
    def value_at(p)
      polynomial.each_with_index.inject(0.0) do |value, (coefficient, degree)|
        value + coefficient.to_f * (p ** degree)
      end
    end

    # Returns exact integer coefficients from degree zero upward.
    def polynomial
      build
      @polynomial ||= evaluate_polynomial(@root)
    end

    # Returns the number of nonterminal shared decision states.
    def state_count
      build
      @states.length
    end

    def self.probability(edges, source, target, probabilities = nil)
      new(edges, source, target, probabilities).probability
    end

    def self.polynomial(edges, source, target)
      new(edges, source, target).polynomial
    end

    private

    def setup_edges(edges)
      @edges = edges
      @edges.each do |edge|
        unless edge.respond_to?(:[]) && edge.respond_to?(:length) && edge.length >= 2
          raise ArgumentError, 'each edge must be a pair [source, target]'
        end
      end

      if @source == @target
        @reachable = true
        return
      end

      forward = Hash.new {|hash, key| hash[key] = []}
      backward = Hash.new {|hash, key| hash[key] = []}
      @edges.each do |edge|
        forward[edge[0]] << edge[1]
        backward[edge[1]] << edge[0]
      end

      from_source = collect(forward, @source)
      to_target = collect(backward, @target)
      relevant_nodes = from_source & to_target
      @reachable = relevant_nodes.include?(@source) && relevant_nodes.include?(@target)

      node_ids = {}
      relevant_nodes.each {|node| node_ids[node] = node_ids.length }

      relevant_edges = []
      relevant_edge_indices = []
      edge_targets = []
      outgoing = Array.new(node_ids.length) { [] }

      @edges.each_with_index do |edge, original_index|
        source_id = node_ids[edge[0]]
        target_id = node_ids[edge[1]]
        next unless source_id && target_id

        edge_id = relevant_edges.length
        relevant_edges << edge
        relevant_edge_indices << original_index
        edge_targets << target_id
        outgoing[source_id] << edge_id
      end

      @edges = relevant_edges
      @edge_indices = relevant_edge_indices
      @edge_targets = edge_targets
      @outgoing = outgoing
      @source_id = node_ids[@source]
      @target_id = node_ids[@target]
    end

    def collect(adjacency, start)
      seen = {start => true}
      stack = [start]
      until stack.empty?
        node = stack.pop
        adjacency[node].each do |next_node|
          next if seen[next_node]
          seen[next_node] = true
          stack << next_node
        end
      end
      seen.keys
    end

    def build
      return if defined?(@root)
      @states = {}

      if @source == @target
        @root = true
      elsif @reachable
        reached = 1 << @source_id
        pending = pending_edges(reached, outgoing_mask(@source_id))
        @root = make_state(reached, pending)
      else
        @root = false
      end
    end

    def outgoing_mask(node)
      @outgoing[node].inject(0) {|mask, edge| mask | (1 << edge)}
    end

    def pending_edges(reached, mask)
      result = 0
      while mask.nonzero?
        bit = lowest_bit(mask)
        edge = bit.bit_length - 1
        result |= bit unless reached_bit?(reached, @edge_targets[edge])
        mask &= mask - 1
      end
      result
    end

    def make_state(reached, pending)
      return true if reached_bit?(reached, @target_id)
      return false if pending.zero?

      key = [reached, pending]
      return @states.fetch(key) if @states.key?(key)

      bit = lowest_bit(pending)
      edge = bit.bit_length - 1
      remaining = pending ^ bit
      dead = make_state(reached, remaining)

      target = @edge_targets[edge]
      alive_reached = reached | (1 << target)
      alive_pending = pending_edges(alive_reached, remaining | outgoing_mask(target))
      alive = make_state(alive_reached, alive_pending)

      state = State.new(edge, dead, alive)
      @states[key] = state
      state
    end

    def reached_bit?(reached, node)
      (reached & (1 << node)).nonzero?
    end

    def lowest_bit(mask)
      mask & -mask
    end

    def evaluate_numeric(terminal, probabilities)
      values = {true => 1, false => 0}
      stack = [terminal]

      until stack.empty?
        node = stack.pop
        next unless node.is_a?(State)
        next if values.key?(node)

        if values.key?(node.dead) && values.key?(node.alive)
          edge_p = edge_probability(node.edge, probabilities)
          values[node] =
            (1 - edge_p) * values.fetch(node.dead) +
            edge_p * values.fetch(node.alive)
        else
          stack << node
          stack << node.dead unless values.key?(node.dead)
          stack << node.alive unless values.key?(node.alive)
        end
      end

      values.fetch(terminal)
    end

    def evaluate_polynomial(terminal)
      values = {true => [1], false => [0]}
      stack = [terminal]

      until stack.empty?
        node = stack.pop
        next unless node.is_a?(State)
        next if values.key?(node)

        if values.key?(node.dead) && values.key?(node.alive)
          values[node] =
            polynomial_add(
              polynomial_multiply(values.fetch(node.dead), [1, -1]),
              polynomial_multiply(values.fetch(node.alive), [0, 1])
            )
        else
          stack << node
          stack << node.dead unless values.key?(node.dead)
          stack << node.alive unless values.key?(node.alive)
        end
      end

      values.fetch(terminal)
    end

    def polynomial_add(left, right)
      size = [left.length, right.length].max
      result = Array.new(size) {|index| left.fetch(index, 0) + right.fetch(index, 0)}
      trim_polynomial(result)
    end

    def polynomial_multiply(left, right)
      return [0] if left == [0] || right == [0]

      result = Array.new(left.length + right.length - 1, 0)
      left.each_with_index do |left_coefficient, left_degree|
        right.each_with_index do |right_coefficient, right_degree|
          result[left_degree + right_degree] +=
            left_coefficient * right_coefficient
        end
      end
      trim_polynomial(result)
    end

    def trim_polynomial(polynomial)
      polynomial.pop while polynomial.length > 1 && polynomial.last.zero?
      polynomial
    end

    def edge_probability(index, probabilities)
      probability =
        case probabilities
        when nil
          edge = @edges.fetch(index)
          edge.length >= 3 ? edge[2] : nil
        when Numeric
          probabilities
        when Array
          probabilities.fetch(@edge_indices.fetch(index))
        else
          unless probabilities.respond_to?(:call)
            raise ArgumentError, 'unsupported probabilities'
          end
          probabilities.call(@edges.fetch(index))
        end

      if probability.nil?
        raise ArgumentError, 'missing probability for edge'
      end
      unless probability.is_a?(Numeric) && probability >= 0 && probability <= 1
        raise ArgumentError, 'edge probability must be between 0 and 1'
      end
      probability
    end
  end
end
