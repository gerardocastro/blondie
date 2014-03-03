require File.expand_path('../spec_helper', __FILE__)

describe Blondie do

  describe '#search' do
    it "should create a new SearchProxy instance" do
      User.search.class.should == Blondie::SearchProxy
    end
    it "should pass the query to the proxy" do
      proxy = Blondie::SearchProxy.new(User, {})
      Blondie::SearchProxy.should_receive(:new).with(anything, name_equals: 'toto').and_return(proxy)
      User.search(name_equals: 'toto').should == proxy
    end
    it "should create a proxy with the right class" do
      proxy = Blondie::SearchProxy.new(User, {})
      Blondie::SearchProxy.should_receive(:new).with(User, anything).and_return(proxy)
      User.search(name_equals: 'toto').should == proxy
    end
  end

  describe '.safe_search' do
    context "when safe_search has not been set" do
      it "should return default value" do
        Blondie.instance_variable_set(:@safe_search, nil)
        Blondie.safe_search.should == Blondie::DEFAULT_SAFE_SEARCH
      end
    end
    context "when safe_search has been set" do
      it "should return selected value" do
        Blondie.instance_variable_set(:@safe_search, false)
        Blondie.safe_search.should == false
      end
    end
  end

  describe '.safe_search=' do
    it "should set safe_search instance variable" do
      Blondie.instance_variable_set(:@safe_search, nil)
      Blondie.safe_search = false
      Blondie.instance_variable_get(:@safe_search).should == false
    end
  end

  describe '#allow_scopes' do
    before do
      @klass = Class.new
      @klass.extend Blondie
    end
    it "should set allowed scopes" do
      @klass.allow_scopes a: 1, b: 2
      @klass.instance_variable_get(:@allowed_scopes).should == {'a' => 1, 'b' => 2}
    end
    it "should add scopes to allowed scopes" do
      @klass.allow_scopes a: 1, b: 2
      @klass.allow_scopes c: 3, d: 4
      @klass.instance_variable_get(:@allowed_scopes).should == {'a' => 1, 'b' => 2, 'c' => 3, 'd' => 4}
    end
  end
  describe '#scope_allowed?' do
    context "when scope is allowed" do
      it "should return true" do
        User.scope_allowed?(:active).should be_true
        User.scope_allowed?('active').should be_true
      end
    end
    context "when scope is not allowed" do
      it "should return false" do
        User.scope_allowed?('foobar').should be_false
      end
    end
  end
  describe '#allowed_scopes' do
    before do
      @klass = Class.new
      @klass.extend Blondie
    end
    context "when no scopes are allowed" do
      it "should return an empty array" do
        @klass.allowed_scopes.should == {}
      end
    end
    context "when scopes are allowed" do
      it "should return allowed scopes" do
        @klass.allow_scopes :a => 1, :b => 2
        @klass.allowed_scopes.should == {'a' => 1, 'b' => 2}
      end
    end
  end
end

describe Blondie::ConditionString do
  context "when the condition is an allowed scope" do
    it "should allow the use of the scope" do
      cs = Blondie::ConditionString.new(User, 'active').parse!
      cs.operator.should == :active
      cs.associations.should == []
      cs.column_name.should be_nil
      cs.modifier.should be_nil
      cs.klass.should == User
    end
  end
  context "when the condition is a column name with an operator" do
    it "should set the right operator and column" do
      cs = Blondie::ConditionString.new(User, 'name_equals').parse!
      cs.operator.should == 'equals'
      cs.column_name.should == 'name'
      cs.klass.should == User
      cs.associations.should == []
      cs.modifier.should be_nil
    end
    context "when operator has a modifier" do
      it "should set the modifier" do
        cs = Blondie::ConditionString.new(User, 'name_equals_any').parse!
        cs.operator.should == 'equals'
        cs.column_name.should == 'name'
        cs.klass.should == User
        cs.associations.should == []
        cs.modifier.should == 'any'
      end
    end
  end
  context "when the condition is about associations" do
    context "when the condition is an allowed scope" do
      it "should allow the use of the scope" do
        cs = Blondie::ConditionString.new(User, 'posts_comments_anonymous').parse!
        cs.operator.should == :anonymous
        cs.associations.should == [:posts, :comments]
        cs.column_name.should be_nil
        cs.modifier.should be_nil
        cs.klass.should == Comment
      end
    end
    context "when the condition is a column name with an operator" do
      it "should set the right operator and column" do
        cs = Blondie::ConditionString.new(User, 'posts_comments_author_equals').parse!
        cs.operator.should == 'equals'
        cs.column_name.should == 'author'
        cs.klass.should == Comment
        cs.associations.should == [:posts, :comments]
        cs.modifier.should be_nil
      end
      context "when operator has a modifier" do
        it "should set the modifier" do
          cs = Blondie::ConditionString.new(User, 'posts_comments_author_equals_any').parse!
          cs.operator.should == 'equals'
          cs.column_name.should == 'author'
          cs.klass.should == Comment
          cs.associations.should == [:posts, :comments]
          cs.modifier.should == 'any'
        end
      end
    end
  end
  context "when condition is not an allowed scope" do
    it "should raise an error" do
      lambda do
        Blondie::ConditionString.new(User, :inactive).parse!
      end.should raise_error Blondie::ConditionNotParsedError
    end
  end
  context "when condition can't be parsed" do
    it "should raise an error" do
      ["comments_author_like", "birthday_is", "name_looks_like"].each do |condition|
        lambda do
          Blondie::ConditionString.new(User, condition).parse!
        end.should raise_error Blondie::ConditionNotParsedError
      end
    end
  end
end

describe Blondie::SearchProxy do

  describe '#method_missing' do
    before do
      @search = User.search
    end
    context "without the '=' operator" do
      context "when method name is a condition" do
        it "should return value if it exists" do
          @search = User.search(name_like: 'toto')
          @search.name_like.should == 'toto'
        end
        it "should return nil if value is not set" do
          @search.name_like.should == nil
        end
      end
      context "when method name is 'order'" do
        it "should return value if it exists" do
          @search = User.search(order: :ascend_by_name)
          @search.order.should == :ascend_by_name
        end
        it "should return nil if value is not set" do
          @search.order.should == nil
        end
      end
      context "when method name is a condition with 'or'" do
        it "should return value if it exists" do
          @search = User.search(name_like_or_login_like: 'toto')
          @search.name_like_or_login_like.should == 'toto'
        end
        it "should return nil if value is not set" do
          @search.name_like_or_login_like.should == nil
        end
      end
      context "when method name is not a condition" do
        it "should raise NoMethodError" do
          lambda do
            @search.foobar
          end.should raise_error NoMethodError
        end
      end
    end
    context "with the '=' operator" do
      context "when method name is a condition" do
        it "should set condition" do
          @search.name_like = 'toto'
          @search.instance_variable_get(:@query)['name_like'].should == 'toto'
        end
      end
      context "when method name is 'order'" do
        it "should set order" do
          @search.order = 'ascend_by_name'
          @search.instance_variable_get(:@query)['order'].should == 'ascend_by_name'
        end
      end
      context "when method name is not a condition" do
        it "should raise NoMethodError" do
          lambda do
            @search.foobar= 'barfoo'
          end.should raise_error NoMethodError
        end
      end
    end
  end

  describe "#result" do
    context "when a block is given" do
      it "should apply block to query before using it" do
        User.search('foobar' => 'barfoo'){|q| q.delete('foobar'); q['name_equals'] = 'Jack'}.result.to_sql.should == %(SELECT "users".* FROM "users"  WHERE "users"."name" = 'Jack')
      end
    end
    it "should stringify the query" do
      proxy = User.search(foobar: 'barfoo')
      proxy.instance_variable_get(:@query).should == { 'foobar' => 'barfoo' }
    end
    context "when one condition is not valid" do
      after do
        Blondie.instance_variable_set(:@safe_search, nil)
      end
      context "when safe search is active" do
        before do
          Blondie.safe_search = true
        end
        it "should return an empty set" do
          User.search(foobar: true).result.should == []
        end
      end
      context "when safe search is not active" do
        before do
          Blondie.safe_search = false
        end
        it "should raise an error" do
          lambda do
            User.search(foobar: true).result
          end.should raise_error Blondie::ConditionNotParsedError
        end
      end
    end

    context "with the order option" do
      it "should use 'ascend' by default" do
        User.search(order: 'name').result.to_sql.should == %(SELECT "users".* FROM "users"   ORDER BY "users"."name" ASC)
      end

      it "should recognize the 'ascend_by' syntax" do
        User.search(order: 'ascend_by_name').result.to_sql.should == %(SELECT "users".* FROM "users"   ORDER BY "users"."name" ASC)
      end

      it "should recognize the 'descend_by' syntax" do
        User.search(order: 'descend_by_name').result.to_sql.should == %(SELECT "users".* FROM "users"   ORDER BY "users"."name" DESC)
      end

      it "should order on association" do
        User.search(order: 'descend_by_posts_comments_author').result.to_sql.should == %(SELECT "users".* FROM "users" INNER JOIN "posts" ON "posts"."user_id" = "users"."id" INNER JOIN "comments" ON "comments"."post_id" = "posts"."id"  ORDER BY "comments"."author" DESC)
      end

      it "should order on scope" do
        User.search(order: 'ascend_by_name_size').result.to_sql.should == %(SELECT "users".* FROM "users"   ORDER BY length("users"."name"))
      end

      context "when order in invalid" do
        context "when safe search is enabled" do
          before do
            Blondie.safe_search = true
          end
          it "should return an empty set" do
            User.search(order: 'toto').result.should == []
          end
        end
        context "when safe search is disabled" do
          before do
            Blondie.safe_search = false
          end
          it "should raise an error" do
            lambda do
              User.search(order: 'toto').result
            end.should raise_error ArgumentError
          end
        end
      end
    end

    context "when search options are nil" do
      it "should not raise an error" do
        User.search(nil).result.to_sql.should == %(SELECT "users".* FROM "users")
      end
    end

    context "when condition is a scope" do
      context "when scope accepts no arguments" do
        it "should ignore scope if value is not '1'" do
          User.search(active: '0').result.to_sql.should == %(SELECT "users".* FROM "users")
        end
        it "should apply scope if value is '1'" do
          User.search(active: '1').result.to_sql.should == %(SELECT "users".* FROM "users"  WHERE "users"."active" = 't')
        end
      end
      context "when scope accepts an argument" do
        it "should pass value to the scope" do
          User.search(id_in_list: '1,2,3').result.to_sql.should == %(SELECT "users".* FROM "users"  WHERE "users"."id" IN (1, 2, 3))
        end
      end
    end

    context "when condition applies to the original class" do
      it "should understand condition that is a scope" do
        User.search(active: '1').result.to_sql.should == %(SELECT "users".* FROM "users"  WHERE "users"."active" = 't')
      end

      describe "the 'like' operator" do
        it "should understand the 'like' operator without modifier" do
          User.search(name_like: 'toto').result.to_sql.should == %(SELECT "users".* FROM "users"  WHERE (("users"."name" LIKE '%toto%')))
        end
        it "should understand the 'like' operator with the 'any' modifier" do
          User.search(name_like_any: ['toto','tutu']).result.to_sql.should == %(SELECT "users".* FROM "users"  WHERE (("users"."name" LIKE '%toto%') OR ("users"."name" LIKE '%tutu%')))
        end
        it "should understand the 'like' operator with the 'all' modifier" do
          User.search(name_like_all: ['toto','tutu']).result.to_sql.should == %(SELECT "users".* FROM "users"  WHERE (("users"."name" LIKE '%toto%') AND ("users"."name" LIKE '%tutu%')))
        end
      end

      describe "the 'equals' operator" do
        it "should understand the 'equals' operator without modifier" do
          User.search(name_equals: 'toto').result.to_sql.should == %(SELECT "users".* FROM "users"  WHERE "users"."name" = 'toto')
        end
        it "should understand the 'equals' operator with the 'any' modifier" do
          User.search(name_equals_any: ['toto','tutu']).result.to_sql.should == %(SELECT "users".* FROM "users"  WHERE ("users"."name" IN ('toto','tutu')))
        end
        it "should understand the 'equals' operator with the 'all' modifier" do
          User.search(name_equals_all: ['toto','tutu']).result.to_sql.should == %(SELECT "users".* FROM "users"  WHERE "users"."name" = 'toto' AND "users"."name" = 'tutu')
        end
        it "should typecast values if needed" do
          User.search(posts_count_equals: '2').result.to_sql.should == %(SELECT "users".* FROM "users"  WHERE "users"."posts_count" = 2)
        end
      end

      context "when condition has 'or' in it" do
        it "should understand full syntax" do
          User.search(name_like_or_login_equals: 'toto').result.to_sql.should == %(SELECT "users".* FROM "users"  WHERE (((("users"."name" LIKE '%toto%')) OR "users"."login" = 'toto')))
        end
        it "should understand partial syntaxt" do
          User.search(name_or_login_like: 'toto').result.to_sql.should == %(SELECT "users".* FROM "users"  WHERE (((("users"."name" LIKE '%toto%')) OR (("users"."login" LIKE '%toto%')))))
        end
        it "should mix scopes and basic operators" do
          User.search(reverse_name_equals_or_id_equals: '1').result.to_sql.should == %(SELECT \"users\".* FROM \"users\" INNER JOIN \"posts\" ON \"posts\".\"user_id\" = \"users\".\"id\" WHERE ((\"users\".\"name\" = '1' OR \"users\".\"id\" = 1)))
        end
      end

    end

    context "when condition applies to an association" do

      it "should understand condition that is a scope" do
        User.search(posts_published: '1').result.to_sql.should == %(SELECT "users".* FROM "users" INNER JOIN "posts" ON "posts"."user_id" = "users"."id" WHERE "posts"."published" = 't')
      end

      it "should understand the 'like' operator" do
        User.search(posts_title_like: 'tutu').result.to_sql.should == %(SELECT "users".* FROM "users" INNER JOIN "posts" ON "posts"."user_id" = "users"."id" WHERE (("posts"."title" LIKE '%tutu%')))
      end

      it "should understand the 'equals' operator" do
        User.search(posts_title_equals: 'tutu').result.to_sql.should == %(SELECT "users".* FROM "users" INNER JOIN "posts" ON "posts"."user_id" = "users"."id" WHERE "posts"."title" = 'tutu')
      end

      it "should not join multiple times" do
        User.search(posts_title_equals: 'tutu', posts_published: '1').result.to_sql.should == %(SELECT "users".* FROM "users" INNER JOIN "posts" ON "posts"."user_id" = "users"."id" WHERE "posts"."title" = 'tutu' AND "posts"."published" = 't')
      end

      it "should chain associations" do
        User.search(posts_comments_anonymous: '1').result.to_sql.should == %(SELECT "users".* FROM "users" INNER JOIN "posts" ON "posts"."user_id" = "users"."id" INNER JOIN "comments" ON "comments"."post_id" = "posts"."id" WHERE ("author" IS NULL))
      end

      context "when condition has 'or' in it" do
        it "should understand full syntax" do
          User.search(posts_favorite_count_equals_or_posts_share_count_equals: 10).result.to_sql.should == %(SELECT "users".* FROM "users" INNER JOIN "posts" ON "posts"."user_id" = "users"."id" WHERE (("posts"."favorite_count" = 10 OR "posts"."share_count" = 10)))
        end
        it "should understand partial syntax" do
          User.search(posts_favorite_count_or_posts_share_count_equals: 10).result.to_sql.should == %(SELECT "users".* FROM "users" INNER JOIN "posts" ON "posts"."user_id" = "users"."id" WHERE (("posts"."favorite_count" = 10 OR "posts"."share_count" = 10)))
        end
      end
    end

  end

  describe Blondie::FormHelper do
    before do
      @helper = Helper.new
    end

    describe '#search_form_for' do
      it "should call search_form" do
        @helper.should_receive(:form_tag).with(nil, { method: :get })
        @helper.search_form_for({})
      end

      it "should call fields_for" do
        search = {a: 1}
        @helper.should_receive(:fields_for).with('q', search)
        @helper.search_form_for(search)
      end

      it "should understand the :as option" do
        search = {a: 1}
        @helper.should_receive(:fields_for).with('f', search)
        @helper.search_form_for(search, as: 'f')
      end
    end
    
  end

end
