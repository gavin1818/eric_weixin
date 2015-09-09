module EricWeixin::Pay
  def self.generate_prepay_id options
    required_field = %i(appid mch_id openid attach body out_trade_no total_fee spbill_create_ip notify_url trade_type)
    query_options = {}
    required_field.each do |p|
      query_options[p] = options[p]
    end
    query_options[:nonce_str] = SecureRandom.uuid.tr('-', '')
    public_account = ::EricWeixin::PublicAccount.find_by_weixin_app_id(options[:appid])

    sign = generate_sign query_options, public_account.mch_key
    last_query_options = query_options
    last_query_options[:sign] = sign
    pay_load = "<xml>#{last_query_options.map { |k, v| "<#{k.to_s}>#{v.to_s}</#{k.to_s}>" }.join}</xml>"
    require 'rest-client'

    response = RestClient.post 'https://api.mch.weixin.qq.com/pay/unifiedorder', pay_load
    pp "**********************下单结果 *********************************"
    pp response.force_encoding("UTF-8")
    result = Hash.from_xml(response.force_encoding("UTF-8"))
    return result['xml']['prepay_id'] if result['xml']['return_code'] == 'SUCCESS'
    nil
  end

  def self.generate_sign options, api_key
    query = options.sort.map do |k,v|
      "#{k.to_s}=#{v.to_s}"
    end.join('&')
    Digest::MD5.hexdigest("#{query}&key=#{api_key}").upcase
  end

  # 参数
  # wxappid
  # re_openid
  # total_amount
  # wishing
  # client_ip
  # act_name
  # remark
  # 使用方法
  #   weixin_user = ::Weixin::WeixinUser.find_by_openid(params[:openid])
  #   public_account = weixin_user.weixin_public_account
  #   options = {}
  #   options[:wxappid] = public_account.weixin_app_id
  #   options[:re_openid] = params[:openid]
  #   options[:total_amount] = params[:total_fee]
  #   options[:wishing] = "恭喜发财"
  #   options[:client_ip] = get_ip
  #   options[:act_name] = "送福利"
  #   options[:remark] = "第一次送"
  #   EricWeixin::Pay.sendredpack options
  def self.sendredpack options
    options[:nonce_str] = SecureRandom.uuid.tr('-', '')
    options[:total_num] = 1
    # 确认公众账号
    public_account = ::EricWeixin::PublicAccount.find_by_weixin_app_id(options[:wxappid])
    options[:mch_id] = public_account.mch_id
    options[:mch_billno] = public_account.mch_id + Time.now.strftime("%Y%m%d") + Time.now.strftime("%H%M%S") + EricTools.generate_random_string(4,1).to_s
    options[:send_name] = public_account.name
    # 生成签名
    sign = generate_sign options, public_account.mch_key
    options[:sign] = sign
    # 生成xml数据包
    pay_load = "<xml>#{options.map { |k, v| "<#{k.to_s}>#{v.to_s}</#{k.to_s}>" }.join}</xml>"
    require 'rest-client'
    ca_path = Rails.root.join("ca/").to_s
    Dir.mkdir ca_path unless Dir.exist? ca_path
    BusinessException.raise '请下载证书' unless Dir.exist?(ca_path+"apiclient_cert.pem") && Dir.exist?(ca_path+"apiclient_key.pem")
    response = RestClient::Request.execute(method: :post, url: 'https://api.mch.weixin.qq.com/mmpaymkttransfers/sendredpack',
                                ssl_client_cert: OpenSSL::X509::Certificate.new(File.read(ca_path+"apiclient_cert.pem")),
                                ssl_client_key:  OpenSSL::PKey::RSA.new(File.read(ca_path+"apiclient_key.pem"), "passphrase, if any"),
                                ssl_ciphers: 'AESGCM:!aNULL',
    payload: pay_load)

    # 分析请求结果
    pp "********************** 发红包 请求结果 ******************************"
    pp response.force_encoding("UTF-8")
    result = Hash.from_xml(response.force_encoding("UTF-8"))
    return true if result['xml']['return_code'] == 'SUCCESS'
    false
  end


end