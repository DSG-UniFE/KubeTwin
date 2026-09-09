# frozen_string_literal: true

module KUBETWIN
  ### Mauro suggested thtat a prioritiy queue would be more efficient than a sorted array for the event queue, so here it is.
  ### We removed the old sorted array implementation, but we kept the same interface for backward compatibility.
  ### We also added a sequence_id to ensure stable ordering of events with the same time, which is important for deterministic behavior.
  class PriorityQueue
    Entry = Struct.new(:time, :sequence_id, :item)

    def initialize(*_args)
      @heap = [nil]
      @next_sequence_id = 0
    end

    def empty?
      @heap.size <= 1
    end

    def size
      @heap.size - 1
    end

    def <<(item)
      insert(item)
      self
    end

    alias push <<
    alias unshift <<

    def insert(*args)
      item = args.length == 1 ? args[0] : args[1]
      entry = Entry.new(item.time, @next_sequence_id, item)
      @next_sequence_id += 1

      @heap << entry
      swim(@heap.size - 1)
      item
    end

    def shift
      return nil if empty?

      min_item = @heap[1].item
      last_index = @heap.size - 1
      exchange(1, last_index)
      @heap.pop
      sink(1) unless empty?
      min_item
    end

    def first
      return nil if empty?

      @heap[1].item
    end

    private

    def exchange(i, j)
      @heap[i], @heap[j] = @heap[j], @heap[i]
    end

    def swim(index)
      while index > 1 && greater?(index / 2, index)
        exchange(index / 2, index)
        index /= 2
      end
    end

    def sink(index)
      last = @heap.size - 1
      while (left = 2 * index) <= last
        child = left
        child += 1 if child < last && greater?(child, child + 1)
        break unless greater?(index, child)

        exchange(index, child)
        index = child
      end
    end

    def greater?(i, j)
      left = @heap[i]
      right = @heap[j]

      return true if left.time > right.time
      return false if left.time < right.time

      left.sequence_id > right.sequence_id
    end
  end
end
