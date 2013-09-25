#

require 'sinatra'
require 'json'
require 'mongo'
require 'uri'

PYTHON = '/usr/bin/python3'
YOU_GET_SCRIPT = '/home/shou/scripts/you-get/you-get'
PROXYCHAINS = '/usr/bin/proxychains'
DOWNLOAD_DIR = '/var/cache/bkget'
DB_NAME = 'bkget'

ENV['LANG'] = 'en_US.UTF-8'
ENV['LC_ALL'] = 'en_US.UTF-8'
ENV['LC_CTYPE'] = 'en_US.UTF-8'


enable :logging
# disable :run, :reload
set :bind, '0.0.0.0'

if RUBY_VERSION =~ /1\.9/
  Encoding.default_external = Encoding::UTF_8
  Encoding.default_internal = Encoding::UTF_8
end


helpers do
  def db
    return @db if @db
    @db = Mongo::MongoClient.new('localhost', 27017)[DB_NAME]
    error 500 unless @db
    return @db
  end

  def allow_access_control
    headers['Access-Control-Allow-Origin'] = '*'
    headers['Access-Control-Allow-Methods'] = 'POST, GET, OPTIONS'
    headers['Access-Control-Max-Age'] = "1728000"
    content_type 'application/javascript'
  end

  def map_extension_name(name)
    mapping = {
        'video/3gpp' => '3gp',
        'video/f4v' => 'flv',
        'video/mp4' => 'mp4',
        'video/MP2T' => 'ts',
        'video/webm' => 'webm',
        'video/x-flv' => 'flv',
        'video/x-ms-asf' => 'asf',
        'audio/mpeg' => 'mp3'
    }
    mapping[name]
  end

  def proxy_needed?(video_url)
    begin
      host = URI(video_url).host
    rescue URI::InvalidURIError
      error 400
    end
    proxied_sites = %w[www.youtube.com vimeo.com www.coursera.org
                       blip.tv dailymotion.com facebook.com
                       plus.google.com www.tumblr.com vine.co
                       soundcloud.com www.mixcloud.com www.freesound.org
                       jpopsuki.tv vid48.com www.nicovideo.jp]
    return proxied_sites.any? {|x| x == host }
  end

  def reset_database
    FileUtils.rm_rf("#{DOWNLOAD_DIR}/.", secure: true)
    db['list'].remove()
  end

  def cache_location(path)
    return path if File.exist? path
    return path + '.download' if File.exist? path + '.download'
    extname = File.extname(File.basename(path))
    path[/#{extname}$/] = '[00]' + extname
    return path if File.exist? path
    return nil
  end

  def kill_dead_tasks
    thread_list = Thread.list.map(&:object_id).map(&:to_s)
    db['list'].find.to_a.each do |rec|
      unless thread_list.include? rec['thread_id']
        db['list'].remove({:object_id => rec['object_id']})
        File.unlink(cache_location(rec['path'])) rescue Errno::ENOENT
      end
    end

  end

end

get '/' do
  send_file 'public/index.html', :type => :html
end

get '/list' do
  allow_access_control

  data = db['list'].find.to_a
  list = data.map do |rec|
    next unless rec['path']
    next unless cache_location(rec['path'])

    downloaded_size = File.size(cache_location(rec['path']))
    status = case rec['status']
             when 'finished' then 'finished'
             when 'downloading'
#               if Thread.list.map(&:object_id).include? rec['thread_id'].to_i
               'downloading'
#               end
             end


    {
      :id => rec['thread_id'].to_s,
      :title => rec['title'],
      :total_size => rec['size'],
      :downloaded_size => downloaded_size,
      :status => status,
      :created_at => rec['created_at'],
      :finished_at => rec['finished_at'],
      :original_url => rec['original_url'],
      :mime_type => rec['mime_type']
    }
  end

  JSON.dump(:list => list.compact.sort_by {|x| x[:created_at]})
end

post '/task' do
  allow_access_control

  url = params['url']

  command = "#{PYTHON} #{YOU_GET_SCRIPT}"
  command = "#{PROXYCHAINS} #{command}" if proxy_needed?(url)
  info = `#{command} -i #{url}`
  md = /.*\n
        Title:\s*(?<title>.*?)\n
        Type:\s*.*\((?<type>.*)\)\n
        Size:.*\((?<size>\d+)\sBytes\)
       /mx.match(info)
  # client error 400: bad request
  error 400 if md.nil?

  title, type, size = md[:title], md[:type], md[:size]

  # client error 409: conflict
  error 409 if Dir.glob(File.join(DOWNLOAD_DIR, title) + '*').length > 0
  logger.info("task added: #{title}, size: #{size}")

  unescaped_title = title.gsub(/[\/\\\*\?]/, '-')
  ext_name = map_extension_name(type) or error 400

  path = File.join(DOWNLOAD_DIR, unescaped_title) + '.' + ext_name

  thread = Thread.new do
    system("#{command} -o #{DOWNLOAD_DIR} #{url}")
    if File.exist?(path)
      db['list'].update({ :thread_id => Thread::current.object_id },
                        { '$set' => { :status => 'finished',
                                      :finished_at => Time.now.to_i } })
    end
  end

  db['list'].insert({
                      :title => title,
                      :size => size.to_i,
                      :path => path,
                      :thread_id => thread.object_id,
                      :status => 'downloading',
                      :created_at => Time.now.to_i,
                      :finished_at => 0,
                      :mime_type => type,
                      :original_url => url
                    })


  # success 201: Created
  status 201
end

get '/task/:id' do
  id = params['id']
  rec = db['list'].find('thread_id' => id.to_i).first
  error 400 if rec.nil?
  not_found unless File.exist? rec['path']
  send_file(rec['path'],
            :filename => File.basename(rec['path']),
            :length => File.size(rec['path']))
end

post '/task/:id/delete' do
  allow_access_control
  id = params['id']
  rec = db['list'].find('thread_id' => id.to_i).first
  error 400 if rec.nil?

  Thread.list.select {|e| e.object_id == id.to_i }.tap{|x| logger.info(x)}.map(&:terminate)
  db['list'].remove('thread_id' => id.to_i).first

  File.unlink(rec['path']) rescue Errno::ENOENT
  File.unlink(rec['path'] + '.download') rescue Errno::ENOENT
end

get '/smile' do
  content_type 'text/plain'
  ':)'
end

get '/reset' do
  error 401 unless params['do'] == 'yes'
  reset_database
  redirect to('smile')
end

get '/test' do
  ENV.inspect
end


#
