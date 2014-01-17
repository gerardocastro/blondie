require 'active_record'

module Blondie

  DEFAULT_SAFE_SEARCH = true

  def self.safe_search=(value)
    @safe_search = !!value
  end

  def self.safe_search
    @safe_search.nil? ? DEFAULT_SAFE_SEARCH : @safe_search
  end

  module FormHelper

    DEFAULT_AS = 'q'

    def search_form_for(search, options = {})
      as = options[:as] || DEFAULT_AS
      form_tag nil, method: :get do
        fields_for(as, search) do |g|
          yield g
        end
      end
    end
  end

  def search(query = {})
    SearchProxy.new(self, (query || {}).stringify_keys)
  end

  def allow_scopes(scopes)
    @allowed_scopes ||= {}
    scopes.each_pair do |scope, arity|
      @allowed_scopes[scope.to_s] = arity
    end
    true
  end

  def allowed_scopes
    @allowed_scopes || {}
  end

  def scope_allowed?(scope_name)
    allowed_scopes.keys.include?(scope_name.to_s)
  end

  class ConditionNotParsedError < ArgumentError; end

  class ConditionString

    OPERATORS = %w(like equals)
    MODIFIERS = %w(all any)

    attr_reader :klass, :column_name, :associations, :string
    attr_accessor :operator, :modifier

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
      if @klass.scope_allowed?(@string)
        @operator = @string.intern
        return self
      end

      # 2. column names
      regexp = /^(#{@klass.column_names.map{|c|Regexp.escape(c)}.join('|')})(_(#{OPERATORS.map{|o|Regexp.escape(o)}.join('|')})(_(#{MODIFIERS.map{|m|Regexp.escape(m)}.join('|')}))?)?$/

      if @string =~ regexp
        @column_name = $1
        @operator = $3
        @modifier = $5
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

      raise ConditionNotParsedError, "#{@string} is not a valid condition"
    end

    def partial?
      @operator.blank?
    end

  end

  class SearchProxy

    META_OPERATOR_OR = ' OR '
    META_OPERATOR_AND = ' AND '
    CHECKBOX_TRUE_VALUE = '1'

    attr_reader :query

    def initialize(klass, query = {})
      @klass = klass
      @query = query || {}
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
    # %{column_name}_or_%{column_name}_%{operator}
    def result
      # The join([]) is here in order to get the proxy instead of the base class.
      # If anyone has a better suggestion on how to achieve the same effect, I'll be glad to hear about it.
      proxy = @klass.joins([])
      @query.each_pair do |condition_string, value|

        next if value.blank?

        begin

          if condition_string == 'order'
            proxy = apply_order proxy, value
          else
            conditions = conditions_from_condition_string condition_string

            raise ConditionNotParsedError, "#{conditions.last.string} should have an operator" if conditions.last.partial?

            proxy = apply_conditions(proxy, conditions, value)
          end
        rescue ArgumentError, ConditionNotParsedError => error
          if Blondie.safe_search
            return @klass.none
          else
            raise error
          end
        end

      end

      proxy
    end

    def apply_order(proxy, order_string)
      if @klass.scope_allowed?(order_string.to_s)
        proxy = proxy.send(order_string)
      else
        order_string.to_s =~ /^((ascend|descend)_by_)?(.*)$/
        direction = $2 == 'descend' ? 'DESC' : 'ASC'
        begin
          condition = ConditionString.new(@klass, $3).parse!
          raise ConditionNotParsedError unless condition.partial?
        rescue ConditionNotParsedError
          raise ArgumentError, "'#{order_string}' is not a valid order string"
        end

        proxy.order! "#{condition.klass.quoted_table_name}.#{condition.klass.connection.quote_column_name(condition.column_name)} #{direction}"
        proxy.joins! chain_associations(condition.associations) unless condition.associations.empty?
      end
      proxy
    end

    def method_missing(method_name, *args, &block)
      method_name.to_s =~ /^([^=]+)(=)?$/
      stringified_method_name = $1
      operator = $2
      begin
        unless @query.has_key?(stringified_method_name) or stringified_method_name == 'order'
          conditions_from_condition_string stringified_method_name
        end
        if operator == '='
          @query[stringified_method_name] = args.first
        end
        return @query[stringified_method_name]
      rescue ConditionNotParsedError
        super method_name, *args, &block
      end
    end

    private

    def conditions_from_condition_string(condition_string)
      begin
        conditions = condition_string.to_s.split('_or_').map{|s| ConditionString.new(@klass, s).parse! }
      rescue ConditionNotParsedError
        conditions = [ConditionString.new(@klass, condition_string).parse!]
      end
      conditions
    end

    def chain_associations(associations)
      associations.reverse[1..-1].inject(associations.last){|m,i| h = {}; h[i] = m; h }
    end

    def apply_conditions(proxy, conditions, value)

      query_chunks = []

      conditions.each do |condition|

        if condition.partial?
          condition.operator = conditions.last.operator
          condition.modifier = conditions.last.modifier
        end

        condition_proxy = @klass

        if condition.associations.any?
          proxy = proxy.joins(chain_associations(condition.associations))
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
          # This is directly applied to the proxy and not the condition_proxy because we cannot use _or_ with scopes.
          case condition.klass.allowed_scopes[condition.operator.to_s]
          when 0
            if value == CHECKBOX_TRUE_VALUE
              proxy = proxy.merge(condition.klass.send(condition.operator))
            end
          else
            proxy = proxy.merge(condition.klass.send(condition.operator, value))
          end
        end

        if condition_proxy != @klass
          condition_proxy.to_sql =~ /WHERE (.*)$/
          query_chunks << $1
        end
      end

      proxy = proxy.where(query_chunks.join(META_OPERATOR_OR)) unless query_chunks.empty?

      proxy
    end

  end

end

ActiveRecord::Base.extend Blondie
