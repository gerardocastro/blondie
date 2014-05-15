require 'active_record'
require 'or_scopes'

module Blondie
  DEFAULT_SAFE_SEARCH = true

  class << self
    attr_writer :safe_search
  end

  def self.safe_search
    @safe_search.nil? ? DEFAULT_SAFE_SEARCH : @safe_search
  end

  module FormHelper
    DEFAULT_AS = 'q'

    def search_form_for(search, options = {})
      as = options.delete(:as) || DEFAULT_AS
      options.reverse_merge!(method: :get)
      form_tag nil, options do
        fields_for(as, search) do |g|
          yield g
        end
      end
    end
  end

  def search(query = nil, &block)
    query ||= {}
    SearchProxy.new(self.current_scope || self.joins([]), query, &block)
  end

  def allow_scopes(scopes)
    allowed_scopes.merge!(scopes)
  end

  def allowed_scopes
    @allowed_scopes ||= ActiveSupport::HashWithIndifferentAccess.new
  end

  def scope_allowed?(scope_name)
    allowed_scopes.key?(scope_name)
  end

  class ConditionNotParsedError < ArgumentError; end

  class ConditionString
    OPERATORS = %w(like equals lower_than greater_than)
    MODIFIERS = %w(all any)

    attr_reader :klass, :column_name, :associations, :string
    attr_accessor :operator, :modifier

    def initialize(klass, string, associations = [], allowed_scopes = nil)
      @string = string.to_s
      @klass = klass
      @allowed_scopes = ActiveSupport::HashWithIndifferentAccess.new(allowed_scopes || {})

      @associations = associations

      @operator = nil
      @column_name = nil
      @modifier = nil
    end

    def scope_arity
      return @allowed_scopes[@string] if scope_allowed?
      return @klass.allowed_scopes[@string.to_s] if class_scope_allowed?

      associations = @associations.join('_')
      association_scopes = @allowed_scopes[associations]
      if association_scopes && association_scopes.key?(@string)
        return @allowed_scopes[associations][@string]
      end
      nil
    end

    def parse!
      # 1. Scopes
      if scope_arity
        @operator = @string.intern
        return self
      end

      # 2. column names
      column_names = @klass.column_names.map { |c| Regexp.escape(c) }.join('|')
      operators = OPERATORS.map { |o| Regexp.escape(o) }.join('|')
      modifiers = MODIFIERS.map { |m| Regexp.escape(m) }.join('|')
      regexp = /^(#{column_names})(_(#{operators})(_(#{modifiers}))?)?$/

      matches = regexp.match(@string)
      if matches
        @column_name = matches.captures[0]
        @operator = matches.captures[2]
        @modifier = matches.captures[4]
        return self
      end

      # 3. Associations
      @klass.reflect_on_all_associations.each do |association|
        matches = /^#{Regexp.escape(association.name)}_(.*)$/.match @string
        next unless matches
        begin
          klass = association.class_name.constantize
          string = matches.captures[0]
          associations = @associations + [association.name]
          return parse_condition_string klass, string, associations
        rescue ConditionNotParsedError
          next
        end
      end

      fail ConditionNotParsedError, "#{@string} is not a valid condition"
    end

    def partial?
      @operator.blank?
    end

    def full_column_name
      "#{quoted_table_name}.#{quoted_column_name}"
    end

    private

    def parse_condition_string(klass, string, associations)
      ConditionString.new(klass, string, associations, @allowed_scopes).parse!
    end

    def quoted_table_name
      klass.quoted_table_name
    end

    def quoted_column_name
      klass.connection.quote_column_name(column_name)
    end

    def scope_allowed?
      @allowed_scopes.key?(@string)
    end

    def class_scope_allowed?
      @klass.scope_allowed?(@string)
    end
  end

  class SearchProxy
    META_OPERATOR_OR = ' OR '
    META_OPERATOR_AND = ' AND '
    CHECKBOX_TRUE_VALUE = '1'

    attr_reader :query, :relation

    def initialize(relation, query = {}, &block)
      @relation = relation
      @query = query.stringify_keys || {}
      @parser = block
    end

    def allowed_scopes
      @allowed_scopes ||= HashWithIndifferentAccess.new
    end

    def allow_scopes(scopes)
      allowed_scopes.merge!(scopes)
    end

    def scope_allowed?(scope_name)
      allowed_scopes.key?(scope_name.to_s) || @relation.klass.scope_allowed?(scope_name)
    end

    # Detected and used:
    #
    # %{col_name}_%{operator}
    # %{scope}
    # %{assoc}_%{col_name}_%{operator}
    # %{assoc}_%{assoc}_%{col_name}_%{operator}
    # %{assoc}_%{scope}
    # %{assoc}_%{assoc}_%{scope}
    # %{col_name}_%{operator}_%{modifier}
    # %{assoc}_%{col_name}_%{operator}_%{modifier}
    # %{assoc}_%{assoc}_%{col_name}_%{operator}_%{modifier}
    # %{col_name}_%{operator}_or_%{col_name}_%{operator}
    # [%{assoc}_]%{col_name}_%{operator}_or_[%{assoc}_]%{col_name}_%{operator}
    # %{col_name}_or_%{col_name}_%{operator}
    # %{col_name}_%{operator}_or_%{scope}
    # %{scope}_or_%{col_name}_%{operator}
    def result
      # The join([]) is here in order to get the proxy instead of the base
      # class. If anyone has a better suggestion on how to achieve the same
      # effect, I'll be glad to hear about it.
      proxy = @relation
      query = @query.dup
      @parser.call(query) if @parser
      query.each_pair do |condition_string, value|

        next if value.blank?

        begin

          if condition_string == 'order'
            proxy = apply_order proxy, value
          else
            conditions = conditions_from_condition_string condition_string

            fail ConditionNotParsedError, "#{conditions.last.string} should have an operator" if conditions.last.partial?

            proxy = apply_conditions(proxy, conditions, value)
          end
        rescue ArgumentError, ConditionNotParsedError => error
          if Blondie.safe_search
            return @relation.none
          else
            raise error
          end
        end

      end

      proxy
    end

    def apply_order(proxy, order_string)
      if scope_allowed?(order_string)
        proxy = proxy.send(order_string)
      else
        matches = /^((ascend|descend)_by_)?(.*)$/.match order_string.to_s
        direction = matches.captures[1] == 'descend' ? 'DESC' : 'ASC'
        begin
          condition = ConditionString.new(@relation.klass, matches.captures[2]).parse!
          fail ConditionNotParsedError unless condition.partial?
        rescue ConditionNotParsedError
          raise ArgumentError, "'#{order_string}' is not a valid order string"
        end

        proxy.order! "#{condition.full_column_name} #{direction}"
        proxy.joins! chain_associations(condition.associations) unless condition.associations.empty?
      end
      proxy
    end

    def method_missing(method_name, *args, &block)
      matches = /^([^=]+)(=)?$/.match method_name.to_s
      stringified_method_name = matches.captures[0]
      operator = matches.captures[1]
      begin
        unless @query.key?(stringified_method_name) ||
               stringified_method_name == 'order'
          conditions_from_condition_string stringified_method_name
        end
        @query[stringified_method_name] = args.first if operator == '='
        return @query[stringified_method_name]
      rescue ConditionNotParsedError
        super method_name, *args, &block
      end
    end

    private

    def conditions_from_condition_string(condition_string)
      begin
        conditions = condition_string.to_s.split('_or_').map do |s|
          ConditionString.new(@relation.klass, s, [], @allowed_scopes).parse!
        end
      rescue ConditionNotParsedError
        conditions = [ConditionString.new(@relation.klass, condition_string, [], @allowed_scopes).parse!]
      end
      conditions
    end

    def chain_associations(associations)
      associations.reverse[1..-1].reduce(associations.last) do |memo, item|
        h = {}
        h[item] = memo
        h
      end
    end

    def apply_conditions(proxy, conditions, value)
      condition_proxy = nil

      conditions.each_with_index do |condition, index|

        if index == 0
          condition_proxy = (condition.klass || proxy).joins([])
        else
          condition_proxy = condition_proxy.or
        end

        if condition.partial?
          condition.operator = conditions.last.operator
          condition.modifier = conditions.last.modifier
        end

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
          sub_conditions = values.map { "(#{condition.full_column_name} LIKE ? ESCAPE '!')" }
          bindings = values.map do |value|
            search_value = value.gsub(/([!_%])/, '!\1')
            matches = search_value.match(/\A'(.*)'\Z/)
            if matches
              matches[1]
            else
              "%#{search_value}%"
            end
          end
          condition_proxy = condition_proxy.where([sub_conditions.join(condition_meta_operator), *bindings])
        when 'equals'
          if condition_meta_operator == META_OPERATOR_OR
            condition_proxy = condition_proxy.where("#{condition.full_column_name} IN (?)", values)
          else
            values.each do |v|
              condition_proxy = condition_proxy.where(condition.klass.table_name => { condition.column_name => v })
            end
          end
        when 'greater_than', 'lower_than'
          values = type_casted_values(condition, values)
          if condition.operator == 'greater_than'
            operator = '>'
            value = condition_meta_operator == META_OPERATOR_AND ? values.max : values.min
          else
            operator = '<'
            value = condition_meta_operator == META_OPERATOR_AND ? values.min : values.max
          end
          condition_proxy = condition_proxy.where("#{condition.full_column_name} #{operator} ?", value)
        else # a scope that has been whitelisted
          case condition.scope_arity
          when 0
            # Arity of the scope is > 0
            if value == CHECKBOX_TRUE_VALUE
              condition_proxy = condition_proxy.send(condition.operator)
            end
          else
            condition_proxy = condition_proxy.send(condition.operator, value)
          end
        end
      end

      proxy = proxy.merge(condition_proxy)

      proxy
    end

    # Type cast all values depending on column
    def type_casted_values(condition, values)
      values.map do |v|
        klass = condition.klass.columns.find do |c|
          c.name == condition.column_name
        end
        klass.type_cast(v)
      end
    end
  end
end

ActiveRecord::Base.extend Blondie
