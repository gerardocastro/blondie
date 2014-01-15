require 'active_record'

module Blondie

  def search(query = {})
    SearchProxy.new(self, query)
  end

  def allow_scopes(*scopes)
    @allowed_scopes ||=[]
    scopes.each do |scope|
      @allowed_scopes << scope.to_s
    end
    true
  end

  def allowed_scopes
    @allowed_scopes || []
  end

  class ConditionNotParsedError < ArgumentError; end

  class ConditionString

    OPERATORS = %w(like equals)
    MODIFIERS = %w(all any)

    attr_reader :klass, :operator, :column_name, :modifier, :associations

    def initialize(klass, condition, associations = [])
      @string = condition.to_s
      @klass = klass

      @associations = associations

      @operator = nil
      @column_name = nil
      @modifier = nil
    end

    def parse!
      # 1. Scopes
      if @klass.allowed_scopes.include?(@string)
        @operator = @string.intern
        return self
      end

      # 2. column names
      regexp = /^(#{@klass.column_names.map{|c|Regexp.escape(c)}.join('|')})_(#{OPERATORS.map{|o|Regexp.escape(o)}.join('|')})(_(#{MODIFIERS.map{|m|Regexp.escape(m)}.join('|')}))?$/

      if @string =~ regexp
        @column_name = $1
        @operator = $2
        @modifier = $4
        return self
      end

      # 3. Associations
      @klass.reflect_on_all_associations.each do |association|
        next unless @string =~ /^#{Regexp.escape(association.name)}_(.*)$/
        begin
          return ConditionString.new(association.class_name.constantize, $1, @associations + [association.name]).parse!
        rescue ConditionNotParsedError
          next
        end
      end

      raise ConditionNotParsedError, @string
    end

  end

  class SearchProxy

    META_OPERATOR_OR = ' OR '
    META_OPERATOR_AND = ' AND '

    def initialize(klass, query = {})
      @klass = klass
      @query = query
    end

    # Detected and used:
    #
    # %{column_name}_%{operator}
    # %{scope}
    # %{association}_%{column_name}_%{operator}
    # %{association}_%{association}_%{column_name}_%{operator}
    # %{association}_%{scope}
    # %{association}_%{association}_%{scope}
    # %{column_name}_%{operator}_%{modifier}
    # %{association}_%{column_name}_%{operator}_%{modifier}
    # %{association}_%{association}_%{column_name}_%{operator}_%{modifier}
    # %{column_name}_%{operator}_or_%{column_name}_%{operator}
    # [%{association}_]%{column_name}_%{operator}_or_[%{association}_]%{column_name}_%{operator}
    #
    # Not detected:
    #
    # %{column_name}_or_%{column_name}_%{operator}
    def result
      result = @klass
      @query.each_pair do |condition_string, value|

        query_chunks = []

        begin
          conditions = condition_string.to_s.split('_or_').map{|s| ConditionString.new(@klass, s).parse! }
        rescue ConditionNotParsedError
          conditions = [ConditionString.new(@klass, condition_string).parse!]
        end

        conditions.each do |condition|

          condition_proxy = @klass

          if condition.associations.any?
            if condition.associations.size == 1
              result = result.joins(condition.associations)
            else
              association_chain = condition.associations.reverse[1..-1].inject(condition.associations.last){|m,i| h = {}; h[i] = m; h }
              result = result.joins(association_chain)
            end
          end

          case condition.modifier
          when 'all'
            values = value
            condition_meta_operator = META_OPERATOR_AND
          when 'any'
            values = value
            condition_meta_operator = META_OPERATOR_OR
          else
            values = [value]
            condition_meta_operator = ''
          end

          case condition.operator
          when 'like'
            sub_conditions = values.map{ "(#{condition.klass.quoted_table_name}.#{condition.klass.connection.quote_column_name(condition.column_name)} LIKE ?)" }
            bindings = values.map{|v| "%#{v}%" }
            condition_proxy = condition_proxy.where([sub_conditions.join(condition_meta_operator), *bindings])
          when 'equals'
            if condition_meta_operator == META_OPERATOR_OR
              condition_proxy = condition_proxy.where("#{condition.klass.quoted_table_name}.#{condition.klass.connection.quote_column_name(condition.column_name)} IN (?)", values)
            else
              values.each do |v|
                condition_proxy = condition_proxy.where(condition.klass.table_name => { condition.column_name => v })
              end
            end
          else # a scope that has been whitelisted
            # This is directly applied to the result and not the condition_proxy because we cannot use _or_ with scopes.
            if value == '1' # @todo isn't it a bit arbitrary? ;)
              # The join([]) is here in order to use 'merge'. If anyone has a better suggestion, I'll be glad to hear about it.
              result = result.joins([]).merge(condition.klass.send(condition.operator))
            end
          end

          if condition_proxy != @klass
            condition_proxy.to_sql =~ /WHERE (.*)$/
            query_chunks << $1
          end
        end

        result = result.where(query_chunks.join(META_OPERATOR_OR)) unless query_chunks.empty?

      end

      result
    end

  end

end

ActiveRecord::Base.extend Blondie
