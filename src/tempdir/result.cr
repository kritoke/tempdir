module TempdirResult
  # Simple generic Result type: either success with a value, or failure with an error
  struct Result(T, E)
    getter ok : Bool
    getter value : T?
    getter error : E?

    def initialize(@ok : Bool, @value : T? = nil, @error : E? = nil)
    end

    def self.ok(value : T)
      Result.new(true, value, nil)
    end

    def self.err(error : E)
      Result.new(false, nil, error)
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
  end
end
