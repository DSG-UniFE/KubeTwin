module KUBETWIN
    class LCG
    # Initialize the LCG with parameters a, c, m, and seed
    def initialize(a=1664525, c=1013904223, m=2**32, seed=12345)
      @a = a
      @c = c
      @m = m
      @seed = seed
      @state = seed
    end
  
    # Generate the next random number in the range [0, 1)
    def next
      @state = (@a * @state + @c) % @m
      @state.to_f
    end
  
    # Generate a sequence of random numbers in the range [0, 1)
    def generate_sequence(n)
      sequence = []
      n.times { sequence << self.next }
      sequence
    end
  end
end
  