
module PostgresExtension
  # A list of SQL commands, from: https://www.postgresql.org/docs/current/sql-commands.html
  # Commands are truncated to their first word, and all duplicates
  # are removed, This favors brevity and low-cardinality over descriptiveness.
  SQL_COMMANDS = %w[
    ABORT
    ALTER
    ANALYZE
    BEGIN
    CALL
    CHECKPOINT
    CLOSE
    CLUSTER
    COMMENT
    COMMIT
    COPY
    CREATE
    DEALLOCATE
    DECLARE
    DELETE
    DISCARD
    DO
    DROP
    END
    EXECUTE
    EXPLAIN
    FETCH
    GRANT
    IMPORT
    INSERT
    LISTEN
    LOAD
    LOCK
    MOVE
    NOTIFY
    PREPARE
    PREPARE
    REASSIGN
    REFRESH
    REINDEX
    RELEASE
    RESET
    REVOKE
    ROLLBACK
    SAVEPOINT
    SECURITY
    SELECT
    SELECT
    SET
    SHOW
    START
    TRUNCATE
    UNLISTEN
    UPDATE
    VACUUM
    VALUES
  ].freeze

  # From: https://github.com/newrelic/newrelic-ruby-agent/blob/9787095d4b5b2d8fcaf2fdbd964ed07c731a8b6b/lib/new_relic/agent/database/obfuscation_helpers.rb#L9-L34
  COMPONENTS_REGEX_MAP = {
    single_quotes: /'(?:[^']|'')*?(?:\\'.*|'(?!'))/,
    dollar_quotes: /(\$(?!\d)[^$]*?\$).*?(?:\1|$)/,
    uuids: /\{?(?:[0-9a-fA-F]\-*){32}\}?/,
    numeric_literals: /-?\b(?:[0-9]+\.)?[0-9]+([eE][+-]?[0-9]+)?\b/,
    boolean_literals: /\b(?:true|false|null)\b/i,
    comments: /(?:#|--).*?(?=\r|\n|$)/i,
    multi_line_comments: %r{\/\*(?:[^\/]|\/[^*])*?(?:\*\/|\/\*.*)}
  }.freeze

  POSTGRES_COMPONENTS = %i[
    single_quotes
    dollar_quotes
    uuids
    numeric_literals
    boolean_literals
    comments
    multi_line_comments
  ].freeze

  UNMATCHED_PAIRS_REGEX = %r{'|\/\*|\*\/|\$(?!\?)}.freeze

  # These are all alike in that they will have a SQL statement as the first parameter.
  # That statement may possibly be parameterized, but we can still use it - the
  # obfuscation code will just transform $1 -> $? in that case (which is fine enough).
  EXEC_ISH_METHODS = %i[
    exec
    query
    sync_exec
    async_exec
    exec_params
    async_exec_params
    sync_exec_params
  ].freeze

  # The following methods all take a statement name as the first
  # parameter, and a SQL statement as the second - and possibly
  # further parameters after that. We can trace them all alike.
  PREPARE_ISH_METHODS = %i[
    prepare
    async_prepare
    sync_prepare
  ].freeze

  # The following methods take a prepared statement name as their first
  # parameter - everything after that is either potentially quite sensitive
  # (an array of bind params) or not useful to us. We trace them all alike.
  EXEC_PREPARED_ISH_METHODS = %i[
    exec_prepared
    async_exec_prepared
    sync_exec_prepared
  ].freeze

  EXEC_ISH_METHODS.each do |method|
    define_method method do |*args|
      span_name, attrs = span_attrs(:query, *args)
      tracer.in_span(span_name, attributes: attrs, kind: :client) do
        super(*args)
      end
    end
  end

  def tracer
    EpsagonPostgresInstrumentation.instance.tracer
  end

  # Rubocop is complaining about 19.31/18 for Metrics/AbcSize.
  # But, getting that metric in line would force us over the
  # module size limit! We can't win here unless we want to start
  # abstracting things into a million pieces.
  def span_attrs(kind, *args) # rubocop:disable Metrics/AbcSize
    if kind == :query
      operation = extract_operation(args[0])
      sql = obfuscate_sql(args[0])
    else
      statement_name = args[0]

      if kind == :prepare
        sql = obfuscate_sql(args[1])
        lru_cache[statement_name] = sql
        operation = 'PREPARE'
      else
        sql = lru_cache[statement_name]
        operation = 'EXECUTE'
      end
    end

    attrs = { 'db.operation' => validated_operation(operation), 'db.postgresql.prepared_statement_name' => statement_name }
    # attrs['db.statement'] = sql if config[:enable_statement_attribute]
    attrs.reject! { |_, v| v.nil? }

    [span_name(operation), client_attributes.merge(attrs)]
  end

  def obfuscate_sql(sql)
    # return sql unless config[:enable_sql_obfuscation]

    # Borrowed from opentelemetry-instrumentation-mysql2
    return 'SQL query too large to remove sensitive data ...' if sql.size > 2000

    # From:
    # https://github.com/newrelic/newrelic-ruby-agent/blob/9787095d4b5b2d8fcaf2fdbd964ed07c731a8b6b/lib/new_relic/agent/database/obfuscator.rb
    # https://github.com/newrelic/newrelic-ruby-agent/blob/9787095d4b5b2d8fcaf2fdbd964ed07c731a8b6b/lib/new_relic/agent/database/obfuscation_helpers.rb
    obfuscated = sql.gsub(generated_postgres_regex, '?')
    obfuscated = 'Failed to obfuscate SQL query - quote characters remained after obfuscation' if PostgresExtension::UNMATCHED_PAIRS_REGEX.match(obfuscated)

    obfuscated
  end

  def span_name(operation)
    [validated_operation(operation), database_name].compact.join(' ')
  end

  def validated_operation(operation)
    operation if PostgresExtension::SQL_COMMANDS.include?(operation)
  end

  def extract_operation(sql)
    # From: https://github.com/open-telemetry/opentelemetry-js-contrib/blob/9244a08a8d014afe26b82b91cf86e407c2599d73/plugins/node/opentelemetry-instrumentation-pg/src/utils.ts#L35
    sql.to_s.split[0].to_s.upcase
  end

  def generated_postgres_regex
    @generated_postgres_regex ||= Regexp.union(PostgresExtension::POSTGRES_COMPONENTS.map { |component| PostgresExtension::COMPONENTS_REGEX_MAP[component] })
  end

  def database_name
    conninfo_hash[:dbname]&.to_s
  end

  def client_attributes
    attributes = {
      'db.system' => 'postgresql',
      'db.user' => conninfo_hash[:user]&.to_s,
      'db.name' => database_name,
      'net.peer.name' => conninfo_hash[:host]&.to_s
    }
    # attributes['peer.service'] = config[:peer_service] if config[:peer_service]

    attributes.merge(transport_attrs).reject { |_, v| v.nil? }
  end

  def transport_attrs
    if conninfo_hash[:host]&.start_with?('/')
      { 'net.transport' => 'Unix' }
    else
      {
        'net.transport' => 'IP.TCP',
        'net.peer.ip' => conninfo_hash[:hostaddr]&.to_s,
        'net.peer.port' => conninfo_hash[:port]&.to_s
      }
    end
  end
end

class EpsagonPostgresInstrumentation < OpenTelemetry::Instrumentation::Base
  install do |_config|
    puts "CALLING INSTALLATION"
    ::PG::Connection.prepend(PostgresExtension)
  end

  present do
    defined?(::PG)
  end
end
