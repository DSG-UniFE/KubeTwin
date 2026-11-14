# frozen_string_literal: true

module KUBETWIN
  ### Mauro suggested thtat a prioritiy queue would be more efficient than a sorted array for the event queue, so here it is.
  ### We removed the old sorted array implementation, but we kept the same interface for backward compatibility.
  ### We also added a sequence_id to ensure stable ordering of events with the same time, which is important for deterministic behavior.
  #
  # Items must respond to #time and #sequence_id= (as Event does); the
  # queue stores them directly rather than wrapping each in an entry.
  class PriorityQueue
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

    alias_method :push, :<<
    alias_method :unshift, :<<

    def insert(*args)
      item = (args.length == 1) ? args[0] : args[1]
      item.sequence_id = @next_sequence_id
      @next_sequence_id += 1

      @heap << item
      swim(@heap.size - 1)
      item
    end

    def shift
      return nil if empty?

      min_item = @heap[1]
      last_index = @heap.size - 1
      exchange(1, last_index)
      @heap.pop
      sink(1) unless empty?
      min_item
    end

    def first
      return nil if empty?

      @heap[1]
    end

    private

    # (A parallel assignment here would allocate an array per swap.)
    def exchange(i, j)
      entry = @heap[i]
      @heap[i] = @heap[j]
      @heap[j] = entry
      nil
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
