require 'spec_helper'
require 'support/adapter/structure'

shared_examples_for 'temporal table' do
  it { expect(adapter.is_chrono?(subject)).to be(true) }

  it { is_expected.to_not have_public_backing }

  it { is_expected.to have_temporal_backing }
  it { is_expected.to have_history_backing }
  it { is_expected.to have_history_extra_columns }
  it { is_expected.to have_history_functions }
  it { is_expected.to have_public_interface }

  it { is_expected.to have_columns(columns) }
  it { is_expected.to have_temporal_columns(columns) }
  it { is_expected.to have_history_columns(columns) }
end

shared_examples_for 'plain table' do
  it { expect(adapter.is_chrono?(subject)).to be(false) }

  it { is_expected.to have_public_backing }

  it { is_expected.to_not have_temporal_backing }
  it { is_expected.to_not have_history_backing }
  it { is_expected.to_not have_history_functions }
  it { is_expected.to_not have_public_interface }

  it { is_expected.to have_columns(columns) }
end

describe ChronoModel::Adapter do
  include ChronoTest::Adapter::Helpers
  include ChronoTest::Adapter::Structure

  describe '.create_table' do
    with_temporal_table do
      it_should_behave_like 'temporal table'
    end

    with_plain_table do
      it_should_behave_like 'plain table'
    end
  end

  describe '.rename_table' do
    renamed = 'foo_table'
    subject { renamed }

    context 'temporal: true' do
      before :all do
        adapter.create_table table, :temporal => true, &columns
        adapter.add_index table, :test
        adapter.add_index table, [:foo, :bar]

        adapter.rename_table table, renamed
      end
      after(:all) { adapter.drop_table(renamed) }

      it_should_behave_like 'temporal table'

      it 'renames indexes' do
        new_index_names = adapter.indexes(renamed).map(&:name)
        expected_index_names = [[:test], [:foo, :bar]].map do |idx_cols|
          "index_#{renamed}_on_#{idx_cols.join('_and_')}"
        end
        expect(new_index_names.to_set).to eq expected_index_names.to_set
      end
    end

    context 'temporal: false' do
      before :all do
        adapter.create_table table, :temporal => false, &columns

        adapter.rename_table table, renamed
      end
      after(:all) { adapter.drop_table(renamed) }

      it_should_behave_like 'plain table'
    end
  end

  describe '.change_table' do
    with_temporal_table do
      before :all do
        adapter.change_table table, :temporal => false
      end

      it_should_behave_like 'plain table'
    end

    with_plain_table do
      before :all do
        adapter.add_index table, :foo
        adapter.add_index table, :bar, :unique => true

        adapter.change_table table, :temporal => true
      end

      it_should_behave_like 'temporal table'

      let(:history_indexes) do
        adapter.on_schema(ChronoModel::Adapter::HISTORY_SCHEMA) do
          adapter.indexes(table)
        end
      end

      it "copies plain index to history" do
        expect(history_indexes.find {|i| i.columns == ['foo']}).to be_present
      end

      it "copies unique index to history without uniqueness constraint" do
        expect(history_indexes.find {|i| i.columns == ['bar'] && i.unique == false}).to be_present
      end
    end

    with_plain_table do
      before :all do
        adapter.change_table table do |t|
          adapter.add_column table, :frupper, :string
        end
      end

      it_should_behave_like 'plain table'

      it { is_expected.to have_columns([['frupper', 'character varying']]) }
    end

    # https://github.com/ifad/chronomodel/issues/91
    context 'given a table using a sequence not owned by a column' do
      before :all do
        adapter.execute 'create sequence temporal.foobar owned by none'
        adapter.execute "create table #{table} (id integer primary key default nextval('temporal.foobar'::regclass), label character varying)"
      end

      after :all do
        adapter.execute "drop table if exists #{table}"
        adapter.execute "drop sequence temporal.foobar"
      end

      it { is_expected.to have_columns([['id', 'integer'], ['label', 'character varying']]) }

      context 'when moving to temporal' do
        before :all do
          adapter.change_table table, temporal: true
        end

        after :all do
          adapter.drop_table table
        end

        it { is_expected.to have_columns([['id', 'integer'], ['label', 'character varying']]) }
        it { is_expected.to have_temporal_columns([['id', 'integer'], ['label', 'character varying']]) }
        it { is_expected.to have_history_columns([['id', 'integer'], ['label', 'character varying']]) }

        it { is_expected.to have_function_source("chronomodel_#{table}_insert", /NEW\.id := nextval\('temporal.foobar'\)/) }
      end
    end
  end

  describe '.drop_table' do
    before :all do
      adapter.create_table table, :temporal => true, &columns

      adapter.drop_table table
    end

    it { is_expected.to_not have_public_backing }
    it { is_expected.to_not have_temporal_backing }
    it { is_expected.to_not have_history_backing }
    it { is_expected.to_not have_history_functions }
    it { is_expected.to_not have_public_interface }
  end

  describe '.add_index' do
    with_temporal_table do
      before :all do
        adapter.add_index table, [:foo, :bar], :name => 'foobar_index'
        adapter.add_index table, [:test],      :name => 'test_index'
      end

      it { is_expected.to have_temporal_index 'foobar_index', %w( foo bar ) }
      it { is_expected.to have_history_index  'foobar_index', %w( foo bar ) }
      it { is_expected.to have_temporal_index 'test_index',   %w( test ) }
      it { is_expected.to have_history_index  'test_index',   %w( test ) }

      it { is_expected.to_not have_index 'foobar_index', %w( foo bar ) }
      it { is_expected.to_not have_index 'test_index',   %w( test ) }
    end

    with_plain_table do
      before :all do
        adapter.add_index table, [:foo, :bar], :name => 'foobar_index'
        adapter.add_index table, [:test],      :name => 'test_index'
      end

      it { is_expected.to_not have_temporal_index 'foobar_index', %w( foo bar ) }
      it { is_expected.to_not have_history_index  'foobar_index', %w( foo bar ) }
      it { is_expected.to_not have_temporal_index 'test_index',   %w( test ) }
      it { is_expected.to_not have_history_index  'test_index',   %w( test ) }

      it { is_expected.to have_index 'foobar_index', %w( foo bar ) }
      it { is_expected.to have_index 'test_index',   %w( test ) }
    end
  end

  describe '.remove_index' do
    with_temporal_table do
      before :all do
        adapter.add_index table, [:foo, :bar], :name => 'foobar_index'
        adapter.add_index table, [:test],      :name => 'test_index'

        adapter.remove_index table, :name => 'test_index'
      end

      it { is_expected.to_not have_temporal_index 'test_index', %w( test ) }
      it { is_expected.to_not have_history_index  'test_index', %w( test ) }
      it { is_expected.to_not have_index          'test_index', %w( test ) }
    end

    with_plain_table do
      before :all do
        adapter.add_index table, [:foo, :bar], :name => 'foobar_index'
        adapter.add_index table, [:test],      :name => 'test_index'

        adapter.remove_index table, :name => 'test_index'
      end

      it { is_expected.to_not have_temporal_index 'test_index', %w( test ) }
      it { is_expected.to_not have_history_index  'test_index', %w( test ) }
      it { is_expected.to_not have_index          'test_index', %w( test ) }
    end
  end

  describe '.add_column' do
    let(:extra_columns) { [['foobarbaz', 'integer']] }

    with_temporal_table do
      before :all do
        adapter.add_column table, :foobarbaz, :integer
      end

      it { is_expected.to have_columns(extra_columns) }
      it { is_expected.to have_temporal_columns(extra_columns) }
      it { is_expected.to have_history_columns(extra_columns) }
    end

    with_plain_table do
      before :all do
        adapter.add_column table, :foobarbaz, :integer
      end

      it { is_expected.to have_columns(extra_columns) }
    end
  end

  describe '.remove_column' do
    let(:resulting_columns) { columns.reject {|c,_| c == 'foo'} }

    with_temporal_table do
      before :all do
        adapter.remove_column table, :foo
      end

      it { is_expected.to have_columns(resulting_columns) }
      it { is_expected.to have_temporal_columns(resulting_columns) }
      it { is_expected.to have_history_columns(resulting_columns) }

      it { is_expected.to_not have_columns([['foo', 'integer']]) }
      it { is_expected.to_not have_temporal_columns([['foo', 'integer']]) }
      it { is_expected.to_not have_history_columns([['foo', 'integer']]) }
    end

    with_plain_table do
      before :all do
        adapter.remove_column table, :foo
      end

      it { is_expected.to have_columns(resulting_columns) }
      it { is_expected.to_not have_columns([['foo', 'integer']]) }
    end
  end

  describe '.rename_column' do
    with_temporal_table do
      before :all do
        adapter.rename_column table, :foo, :taratapiatapioca
      end

      it { is_expected.to_not have_columns([['foo', 'integer']]) }
      it { is_expected.to_not have_temporal_columns([['foo', 'integer']]) }
      it { is_expected.to_not have_history_columns([['foo', 'integer']]) }

      it { is_expected.to have_columns([['taratapiatapioca', 'integer']]) }
      it { is_expected.to have_temporal_columns([['taratapiatapioca', 'integer']]) }
      it { is_expected.to have_history_columns([['taratapiatapioca', 'integer']]) }
    end

    with_plain_table do
      before :all do
        adapter.rename_column table, :foo, :taratapiatapioca
      end

      it { is_expected.to_not have_columns([['foo', 'integer']]) }
      it { is_expected.to have_columns([['taratapiatapioca', 'integer']]) }
    end
  end

  describe '.change_column' do
    with_temporal_table do
      before :all do
        adapter.change_column table, :foo, :float
      end

      it { is_expected.to_not have_columns([['foo', 'integer']]) }
      it { is_expected.to_not have_temporal_columns([['foo', 'integer']]) }
      it { is_expected.to_not have_history_columns([['foo', 'integer']]) }

      it { is_expected.to have_columns([['foo', 'double precision']]) }
      it { is_expected.to have_temporal_columns([['foo', 'double precision']]) }
      it { is_expected.to have_history_columns([['foo', 'double precision']]) }
    end

    with_plain_table do
      before(:all) do
        adapter.change_column table, :foo, :float
      end

      it { is_expected.to_not have_columns([['foo', 'integer']]) }
      it { is_expected.to have_columns([['foo', 'double precision']]) }
    end
  end

  describe '.remove_column' do
    with_temporal_table do
      before :all do
        adapter.remove_column table, :foo
      end

      it { is_expected.to_not have_columns([['foo', 'integer']]) }
      it { is_expected.to_not have_temporal_columns([['foo', 'integer']]) }
      it { is_expected.to_not have_history_columns([['foo', 'integer']]) }
    end

    with_plain_table do
      before :all do
        adapter.remove_column table, :foo
      end

      it { is_expected.to_not have_columns([['foo', 'integer']]) }
    end
  end

end
