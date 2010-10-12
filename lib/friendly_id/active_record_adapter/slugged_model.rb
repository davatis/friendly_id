module FriendlyId
  module ActiveRecordAdapter
    module SluggedModel

      def self.included(base)
        base.class_eval do
          has_many :slugs, :order => 'id DESC', :as => :sluggable, :dependent => :destroy
          # deaktiviert wegen i18n
          #has_one :slug, :order => 'id DESC', :as => :sluggable, :dependent => :destroy
          before_save :save_slugs
          after_save :set_slug_cache
          after_update :update_scope
          after_update :update_dependent_scopes
          protect_friendly_id_attributes
          extend FriendlyId::ActiveRecordAdapter::Finders unless FriendlyId.on_ar3?
          define_method("#{friendly_id_config.method}=") do |*args|
            #p 'setter'
            super
            build_a_slug # if args[0] == friendly_id_config.method.to_s
          end
        end
      end

      include FriendlyId::Slugged::Model

      def locale
        I18n.locale
      end


      def write_attribute *args
        #p 'write attribute'
        #p args
        #p friendly_id_config.method
        super *args
        if args[0].to_s == friendly_id_config.method.to_s
          @value = args[1]
          build_a_slug 
        end
      end

      def slug
        #p 'method :slug in slugged_model'
        @slug ||= {}
        #p @slug
        #p slugs
        #p slugs.with_locale(locale)
        (@slug && @slug[locale]) || @slug[locale] = slugs.with_locale(locale).first
        #p @slug
        #p "returning #{@slug[locale]} as slug"
        @slug[locale]
      end

      def find_slug(name, sequence)
        slugs.find_by_name_and_sequence_and_locale(name, sequence, locale)
      end

      # Returns the friendly id, or if none is available, the numeric id. Note that this
      # method will use the cached_slug value if present, unlike {#friendly_id}.
      def to_param
        friendly_id_config.cache_column ? to_param_from_cache : to_param_from_slug
      end

      private

      def scope_changed?
        friendly_id_config.scope? && send(friendly_id_config.scope).to_param != slug.scope
      end

      # Respond with the cached value if available.
      def to_param_from_cache
        read_attribute(friendly_id_config.cache_column) || id.to_s
      end

      # Respond with the slugged value if available.
      def to_param_from_slug
        slug? ? slug.to_friendly_id : id.to_s
      end

      # Build the new slug using the generated friendly id.
      def build_a_slug
        #p' build a slug'
        return unless new_slug_needed?
        #p 'new slug needed'
        raise "steht schon was anderes drin #{@slug.inspect} - #{locale}" if @slug != nil && !@slug.kind_of?(Hash)
        @slug ||= {} #if @slug == nil
        #p slug_text
        #p self
        @slug[locale] = slugs.build :name => slug_text.to_s, :scope => friendly_id_config.scope_for(self),
          :sluggable => self, :locale => locale
        #raise @slug.inspect
        #p @slug
        #raise locale.inspect
        #raise @slug[locale].inspect
        @new_friendly_id = @slug[locale].to_friendly_id
      end

      def save_slugs
        #p 'save slugs'
        if @slug && @slug.kind_of?( Hash )
          #p @slug
          @slug.each do |k, v|
            #p "nil #{k} => #{v}" unless v
            if v && v.new_record?
              v.sluggable = self
              #p "saving slug #{v.name}"
              v.save!
            end
          end
        end
        true
      end

      # Reset the cached friendly_id?
      def new_cache_needed?
        uses_slug_cache? && slug? && send(friendly_id_config.cache_column) != slug.to_friendly_id
      end

      # Reset the cached friendly_id.
      def set_slug_cache
        if new_cache_needed?
          begin
            send "#{friendly_id_config.cache_column}=", slug.to_friendly_id
            update_without_callbacks
          rescue ActiveRecord::StaleObjectError
            reload
            retry
          end
        end
      end

      def update_scope
        return unless slug && scope_changed?
        self.class.transaction do
          slug.scope = send(friendly_id_config.scope).to_param
          similar = Slug.similar_to(slug)
          if !similar.empty?
            slug.sequence = similar.first.sequence.succ
          end
          slug.save!
        end
      end

      # Update the slugs for any model that is using this model as its
      # FriendlyId scope.
      def update_dependent_scopes
        return unless friendly_id_config.class.scopes_used?
        if slugs(true).size > 1 && @new_friendly_id
          friendly_id_config.child_scopes.each do |klass|
            Slug.update_all "scope = '#{@new_friendly_id}'", ["sluggable_type = ? AND scope = ?",
              klass.to_s, slugs.second.to_friendly_id]
          end
        end
      end

      # Does the model use slug caching?
      def uses_slug_cache?
        friendly_id_config.cache_column?
      end

      # This method was removed in ActiveRecord 3.0.
      if !ActiveRecord::Base.private_method_defined? :update_without_callbacks
        def update_without_callbacks
          attributes_with_values = arel_attributes_values(false, false, attribute_names)
          return false if attributes_with_values.empty?
          self.class.unscoped.where(self.class.arel_table[self.class.primary_key].eq(id)).arel.update(attributes_with_values)
        end
      end
    end
  end
end
