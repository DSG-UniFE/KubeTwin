require 'ffi'

module PRandom
  extend FFI::Library
  ffi_lib '/Users/filippopoltronieri/code/KubeTwin/libprandom.dylib'
  attach_function :prandom_u32, [], :uint32

  def self.normalized_random
    prandom_u32.to_f
  end
end


