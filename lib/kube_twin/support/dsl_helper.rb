# frozen_string_literal: true

# taken from Jim Freeze's excellent article "Creating DSLs with Ruby"
# http://www.artima.com/rubycs/articles/ruby_as_dsl.html

class Module
  def dsl_accessor(*symbols)
    symbols.each { |sym|
      class_eval %{
        def #{sym}(*val)
          if val.empty?
            @#{sym}
          else
            @#{sym} = val.size == 1 ? val[0] : val
          end
        end
      }
    }
  end
end
