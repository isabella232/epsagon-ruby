RSpec.shared_examples 'HTTP Request with metadata_only' do
  it 'has one finished span' do
    expect(exporter.finished_spans.size).to eq 1
  end

  it 'has the correct span name' do
    expect(span.name).to eq 'example.com'
  end

  it 'has "operation" set' do
    expect(span.attributes['operation']).to eq 'GET'
  end

  it 'has "http.scheme" set' do
    expect(span.attributes['http.scheme']).to eq 'http'
  end

  it 'has "http.status_code" set' do
    expect(span.attributes['http.status_code']).to eq 200
  end

  it 'has "http.request.path" set' do
    expect(span.attributes['http.request.path']).to eq '/success'
  end

  it 'has correct span kind' do
    expect(span.kind).to eq :client
  end

  it 'does not have "http.request.path_params"' do
    expect(span.attributes['http.request.path_params']).to be nil
  end

  it 'does not have "http.request.query"' do
    expect(span.attributes['http.request.query']).to be nil
  end

  it 'does not have "http.request.query_params"' do
    expect(span.attributes['http.request.query_params']).to be nil
  end

  it 'does not have "http.request.body"' do
    expect(span.attributes['http.request.body']).to be nil
  end

  it 'does not have "http.request.headers"' do
    expect(span.attributes['http.request.headers']).to be nil
  end

  it 'does not have "http.response.body"' do
    expect(span.attributes['http.response.body']).to be nil
  end

  it 'does not have "http.response.headers"' do
    expect(span.attributes['http.response.headers']).to be nil
  end

  it 'does not have "http.request.headers.User-Agent"' do
    expect(span.attributes['http.request.headers.User-Agent']).to be nil
  end
end

RSpec.shared_examples 'HTTP Request with metadata_only: false' do |options = {}|
  it 'has one finished span' do
    expect(exporter.finished_spans.size).to eq 1
  end

  it 'has the correct span name' do
    expect(span.name).to eq 'example.com'
  end

  it 'has "operation" set' do
    expect(span.attributes['operation']).to eq 'GET'
  end

  it 'has "http.scheme" set' do
    expect(span.attributes['http.scheme']).to eq 'http'
  end

  it 'has "http.status_code" set' do
    expect(span.attributes['http.status_code']).to eq 200
  end

  it 'has "http.request.path" set' do
    expect(span.attributes['http.request.path']).to eq '/success'
  end

  it 'has correct span kind' do
    expect(span.kind).to eq :client
  end

  it 'has "http.request.path_params"' do
    expect(span.attributes['http.request.path_params']).to be nil
  end

  it 'has "http.request.query"' do
    expect(span.attributes['http.request.query']).to be nil
  end

  if options.fetch(:query_params, false)
    it 'has "http.request.query_params"' do
      expect(span.attributes['http.request.query_params']).to_not be nil
    end
  else
    it 'has empty "http.request.query_params"' do
      expect(span.attributes['http.request.query_params']).to be nil
    end
  end

  it 'has "http.request.body"' do
    expect(span.attributes['http.request.body']).to be nil
  end

  it 'has "http.request.headers"' do
    headers = JSON.parse(span.attributes['http.request.headers'])
    expect(headers.keys.length).to be > 0
  end

  it 'has "http.response.body"' do
    expect(span.attributes['http.response.body']).to_not be nil
  end

  it 'has "http.response.headers"' do
    expect(span.attributes['http.response.headers']).to_not be nil
  end

  it 'has "http.request.headers.User-Agent"' do
    expect(span.attributes['http.request.headers.User-Agent']).to_not be nil
  end
end