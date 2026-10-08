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

## Counting Eulerian circuits

`TSort.count_eulerian_circuits` counts the Eulerian circuits of a directed
multigraph given as a node list and an edge list of `[tail, head]` pairs.
Parallel edges and loops are allowed, and every edge has its own identity.
The count uses the BEST theorem (a directed spanning-tree cofactor times
out-degree factorial factors), so it returns an exact Integer without
enumerating the circuits.

```ruby
TSort.count_eulerian_circuits([:a, :b],
                              [[:a, :b], [:a, :b], [:b, :a], [:b, :a]],
                              start: :a)
#=> 2
```

The counting convention fixes the start node (`start:`) and the first
traversed edge (`first_edge:`, an index into the edge list, default 0).
See the method documentation for how to convert the result to other
conventions (any first edge, cyclic orders, any start node) and for the
definitions of the degenerate cases (an empty graph or a single isolated
node counts as one circuit when `start` is a declared node).

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ruby/tsort.
