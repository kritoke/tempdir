module TempdirResult
  # Simple generic Result type: either success with a value, or failure with an error
  struct Result(T, E)
    getter ok : Bool
    getter value : T?
    getter error : E?

    def initialize(@ok : Bool, @value : T? = nil, @error : E? = nil)
    end

    def self.ok(value : T) : Result(T, E)
      Result(T, E).new(true, value, nil)
    end

    def self.err(error : E) : Result(T, E)
      Result(T, E).new(false, nil, error)
    end

    def success? : Bool
      @ok
    end

    def value! : T
      @value.not_nil!
    end

    def error! : E
      @error.not_nil!
    end

    # Transform the success value
    def map(&block : T -> U) : Result(U, E)
      if @ok
        Result(U, E).ok(block.call(@value.not_nil!))
      else
        Result(U, E).err(@error.not_nil!)
      end
    end

    # Chain another Result-producing function
    def and_then(&block : T -> Result(U, E)) : Result(U, E)
      if @ok
        block.call(@value.not_nil!)
      else
        Result(U, E).err(@error.not_nil!)
      end
    end

    # Return the contained value or a default
    def unwrap_or(default : T) : T
      @ok ? @value.not_nil! : default
    end
  end
end
