# Heavily inspired by Noel Rappin's "More Named Scope Awesomeness"
# http://www.pathf.com/blogs/2008/06/more-named-scope-awesomeness/

module ActiveRecord
  # raised when filter_by is called with an attribute that has not been 
  # whitelisted for being filtered
  class IllegalAttributeAccessError < ActiveRecordError
    attr_reader :attribute
    def initialize(attribute)
      @attribute = attribute
      super "Tried to filter by #{attribute.inspect} although this attribute has not been whitelisted for filtering."
    end
  end

  module HasFilter
    class << self
      def included(base)
        base.send :extend, ActMacro

        base.class_eval do
          scopes = { # FIXME make this writable
            :contains            => ["LIKE",     "%%%s%"],
            :does_not_contain    => ["NOT LIKE", "%%%s%"],
            :starts_with         => ["LIKE",     "%s%"  ],
            :does_not_start_with => ["NOT LIKE", "%s%"  ],
            :ends_with           => ["LIKE",     "%%%s" ],
            :does_not_end_with   => ["NOT LIKE", "%%%s" ],
            :is                  => ["=" ],
            :is_not              => ["<>"] }
            # created_before, created_after
            # updated_before, updated_after
            # author name, email

          scopes.each do |name, scope|
            named_scope name, lambda { |column, value|
              { :conditions => filter_condition(column, value, *scope) } 
            }
          end
          
          named_scope :contains_all_of, lambda { |column, values|
            values = values.split(' ') if values.is_a?(String)
            values.map! { |value| "%#{value}%" }
            { :conditions => [(["#{column} LIKE ?"] * values.size).join(' AND '), *values] }
          }
          
          # seems to be in rails now
          # named_scope :scoped, lambda { |scope| scope }
        end
      end
    end

    module ActMacro
      def has_filter(*args)
        return if has_filter?
        include InstanceMethods
        extend ClassMethods
        
        # make it so that the frontend filter bar can be autogenerated from
        # whatever was defined here. maybe reflect on the attribute column types
        # and map certain possible filter types to them (like strings can be
        # filtered by is, is_not, ...) also add filter types based on model
        # properties like has_author, acts_as_taggable etc. and explicitely 
        # add options e.g. for assets (is_media_type)
        
        options = args.extract_options!
        class_inheritable_accessor  :filterable_attributes
        write_inheritable_attribute :filterable_attributes, args
      end
    
      def has_filter?
        included_modules.include? ActiveRecord::HasFilter::InstanceMethods
      end
      
      def filter_condition(column, value, operator, format = nil)
        values = Array(value)
        query = (["lower(#{column}) #{operator} ?"] * values.size).join(' OR ')
        values = values.map{ |value| format ? format % value : value }.map(&:downcase)
        [query, *values]
      end
    end
  
    module ClassMethods
      # Person.filter_by first_name, :starts_with, "john"
      # Person.filter_by [:first_name, :starts_with, "john"], [:last_name, "contains", "doh"]
      def filter_by(*criteria)
        if criteria.first.is_a?(Array)
          criteria.inject(scoped({})) do |scope, criterion|
            scope.scoped(filter_by(*criterion).proxy_options) if criterion
          end
        elsif criteria.first
          # named_scopes don't seem to have access to their owner class, so we got to check this here?
          guard_attribute_access!(criteria.second)
          send(*criteria) 
        else
          scoped({})
        end
      end
      
      protected
      
        def guard_attribute_access!(attribute)
          if column_names.include?(attribute.try(:to_s)) && 
             !filterable_attributes.include?(attribute.try(:to_sym))
            raise IllegalAttributeAccessError.new(attribute)
          end
        end
    end

    module InstanceMethods
    end
  end
end

ActiveRecord::Base.send :include, ActiveRecord::HasFilter
