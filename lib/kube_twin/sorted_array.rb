# frozen_string_literal: true

module KUBETWIN
  # the SortedArray class was taken from the ruby cookbook
  class SortedArray < Array
    def initialize(*args, &sort_by)
      @sort_by = sort_by || Proc.new { |x,y| x <=> y }
      super(*args)
      sort!(&sort_by)
    end

    def insert(i, v)
      if size == 0 or v < self[0]
        super(0, v)
      elsif v > self[-1]
        super(-1, v)
      else
        left = 0
        right = size - 1
        middle = (left + right)/2
        while left < right
          if v >= self[middle]
            left = middle + 1
          else
            right = middle
          end
          middle = (left + right)/2
        end
        super(middle, v)
      end
    end

    def <<(el)
      insert(0, el)
    end

    alias push <<
    alias unshift <<

    # some methods, like collect!, can modify the items in an array,
    # taking them out of sort order. we need to redefine those
    # methods.
    # we can't use define_method to define these methods because in
    # Ruby 1.8 you can't use define_method to create a method that
    # takes a block argument.
    [ "collect!", "flatten!", "[]=" ].each do |method_name|
      class_eval %{
        def #{method_name}(*args)
          super
          sort! &@sort_by
        end
      }
    end

    def reverse!
      # do nothing: reversing the array would disorder it.
    end
  end
end
