# TSort

TSort implements topological sorting using Tarjan's algorithm for
strongly connected components.

TSort is designed to be able to be used with any object which can be
interpreted as a directed graph.

TSort requires two methods to interpret an object as a graph,
`tsort_each_node` and `tsort_each_child`.

* `tsort_each_node` is used to iterate for all nodes over a graph.
* `tsort_each_child` is used to iterate for child nodes of a given node.

The equality of nodes are defined by eql? and hash since
TSort uses Hash internally.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'tsort'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install tsort

## Usage

The following example demonstrates how to mix the TSort module into an
existing class (in this case, Hash). Here, we're treating each key in
the hash as a node in the graph, and so we simply alias the required
`#tsort_each_node` method to Hash's `#each_key` method. For each key in the
hash, the associated value is an array of the node's child nodes. This
choice in turn leads to our implementation of the required `#tsort_each_child`
method, which fetches the array of child nodes and then iterates over that
array using the user-supplied block.

```ruby
require 'tsort'

class Hash
  include TSort
  alias tsort_each_node each_key
  def tsort_each_child(node, &block)
    fetch(node).each(&block)
  end
end

{1=>[2, 3], 2=>[3], 3=>[], 4=>[]}.tsort
#=> [3, 2, 1, 4]

{1=>[2], 2=>[3, 4], 3=>[2], 4=>[]}.strongly_connected_components
#=> [[4], [2, 3], [1]]
```

## Network Reliability

TSort::Reliability computes the probability that a source node can
still reach a sink node when every directed edge survives independently
with its own probability.  Edges are independent, paths are not: routes
sharing a common bridge edge are accounted for exactly.  The
computation uses a frontier-based decision diagram with shared states
instead of enumerating all 2**E subgraphs, and reports the number of
states it needed.

```ruby
require 'tsort'

# Two routes (via :a or via :b) sharing the bridge edge :x->:t.
edges = [[:s, :a], [:s, :b], [:a, :x], [:b, :x], [:x, :t]]
rel = TSort::Reliability.new(edges)

# Numeric: one survival probability per edge.
rel.probability(:s, :t, [0.9, 0.9, 0.9, 0.9, 0.99])

# Exact integer-coefficient polynomial when every edge uses the same
# variable p (coefficient at index k multiplies p**k).
rel.polynomial(:s, :t)
#=> [0, 0, 0, 2, 0, -1]   # 2*p**3 - p**5

# Number of decision-diagram states, for inspection.
rel.state_count(:s, :t)
```

Parallel edges between the same pair of nodes are merged into one
equivalent edge, and self-loops are ignored.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ruby/tsort.
