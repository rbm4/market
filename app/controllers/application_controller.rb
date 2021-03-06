class ApplicationController < ActionController::Base
  require 'rest-client'
  require 'sendgrid-ruby'
  require 'coinbase/wallet'
  include SendGrid
  require 'blockchain'
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  skip_before_action :verify_authenticity_token, :only => [:test_post]
  helper_method :bitcoinpay
  protect_from_forgery with: :exception
  attr_accessor :viewname
  helper_method :limite_compra_btc, :confirmar_email, :limite_compra_ltc, :useremail, :current_user, :current_order, :has_order?, :username, :receber_pagamento, :moeda, :buy, :convert_bitcoin, :is_admin?, :archive_wallet, :itens_string, :params_post, :userphone, :captcha
  after_filter :cors_set_access_control_headers
  helper_method :wich_status, :brl_btc, :bitcoin_para_real, :type, :standard_conversion, :litecoin_para_bitcoin, :config_block, :litecoin_para_x_bitcoin, :block_address, :balance_btc_coinbase, :parabenizar_ganho, :validate_operation, :consulta_saldo_cripto, :last_order_exchange, :total_usuario_saldo, :get_saldo, :cpt_transaction_user, :add_saldo, :set_pair
  #mneconic 'icon monkey curtain tomorrow guard above genuine episode rival palm frame disease'

  #heroku email
  def set_pair(string)
    hash, base = last_order_exchange(string)
    if hash["#{string}/last_buy"] == nil
      buy_string = "-------"
    else
      buy_string = hash["#{string}/last_buy"]
    end
    if hash["#{string}/last_sell"] == nil
      sell_string = "-------"
    else
      sell_string = hash["#{string}/last_sell"]
    end
    @buy = "#{buy_string} #{base}"
    p @buy
    @sell = "#{sell_string} #{base}"
  end
  def cpt_transaction_user(user,id,username,email)
        url = URI.parse('https://cpttransactions.herokuapp.com/add_users')
        req = Net::HTTP::Post.new(url.request_uri)
        req.set_form_data({'username'=> username, 'email'=> email, 'id_original'=> id, 'name'=> user})
        http = Net::HTTP.new(url.host, url.port)
        http.use_ssl = (url.scheme == "https")
        response = http.request(req)
        response
  end
  def add_saldo(usuario,moeda,qtd,tipo) #função para adicionar saldo em depóstios
    url = URI.parse('https://cpttransactions.herokuapp.com/add_saldo')
    req = Net::HTTP::Post.new(url.request_uri)
    req.set_form_data({'username'=> usuario.username, 'id_original'=> usuario.id, 'currency'=>moeda, 'amount'=>qtd, 'type'=>tipo})
    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = (url.scheme == "https")
    response = http.request(req)
    p response.body
    response.body
  end
  def get_saldo(usuario)
    url = URI.parse('https://cpttransactions.herokuapp.com/get_saldo')
    req = Net::HTTP::Post.new(url.request_uri)
    req.set_form_data({'username'=> usuario.username, 'id_original'=> usuario.id})
    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = (url.scheme == "https")
    response = http.request(req)
    p response.body
    response.body
  end
  def cpt_transaction_add(currency,type,user_id,debit_credit,amount)
    url = URI.parse('https://cpttransactions.herokuapp.com/add_transaction')
    req = Net::HTTP::Post.new(url.request_uri)
    req.set_form_data({'currency'=> currency, 'type'=> type, 'user_id'=> user_id, 'debit_credit'=> debit_credit, 'amount'=> amount})
    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = (url.scheme == "https")
    response = http.request(req)
    response
  end
  def require_login
    if current_user != nil
      return true
    end
    redirect_to '/login'
  end
  def total_usuario_saldo
    # string_moeda == "lct", "btc", "doge", "tltc", "tbtc", "tdoge"
    all_users = Usuario.all
    sum = BigDecimal(0,8)
    saldo_total_hash = {} #hashtable que vai conter o saldo total de dogecoin bitcoin e litecoin
    moedas_a_percorrer = ["doge","ltc","btc","brl"]
    all_users.each do |m|
      saldo_hash = eval(m.saldo_encrypted)
      moedas_a_percorrer.each do |k|
        if saldo_total_hash["#{k}"] == nil
          saldo_total_hash["#{k}"] = 0
        end
        saldo_total_hash["#{k}"] = (BigDecimal(saldo_total_hash["#{k}"],8) + BigDecimal(saldo_hash["#{k.upcase}"],8)).to_s
      end
    end
    #saldo de todos os usuários salvo
    consulta = Exchangeorder.where("status = :stt", {stt: "open"})
    p saldo_total_hash #Saldo total "em saldo" de todos 1 usuário, ao finalizar execução de linha 31 terá saldo completo
    #consulta = Exchangeorder.where("user = :usuario AND status = :stt", {usuario: m.username, stt: "open"}) #adicionar saldo de ordens abertas daquele usuário "m" da linha 31
    if consulta != nil
      consulta.each do |n|
        # Informações da ordem "n"
        par = n.par.split("/")
        moeda1 = par[0]
        moeda2 = par[1]
        amount = BigDecimal(n.amount,8)
        price = BigDecimal(n.price,8)
      #
        
        if n.tipo == "buy" #comprar determinada quantidade de moeda1 usando moeda2, valor total em moeda2 é a multiplicação de moeda1 (amount) com moeda2 (price) resultado em moeda2
          saldo_total_hash["#{moeda2.downcase}"] = (BigDecimal(saldo_total_hash["#{moeda2.downcase}"],8) + (amount * price)).to_s
        elsif n.tipo == "sell" #tentativa de venda de moeda1 para receber moeda2, usuário tem saldo "amount" em moeda1, somar moeda 1 no saldo
          saldo_total_hash["#{moeda1.downcase}"] = (BigDecimal(saldo_total_hash["#{moeda1.downcase}"],8) + amount).to_s
        end
        
      end
      #Saldo de ordem "n" aberta pertencente ao usuário "m" somada em seu respectivo valor de "crédito"
    end
    return saldo_total_hash
  end
  def last_order_exchange(string_par)
    base_currency = string_par.split("/")[1]
    h = {}
    consulta = (Exchangeorder.where("par = :str_par AND tipo = :type AND status = :stt", {str_par: string_par, type: "buy", stt: "executada"}).last)
    if consulta != nil
      h["#{string_par}/last_buy"] = consulta.price
    end
    consulta_sell = (Exchangeorder.where("par = :str_par AND tipo = :type AND status = :stt", {str_par: string_par, type: "sell", stt: "executada"}).last)
    if consulta_sell != nil
      h["#{string_par}/last_sell"] = consulta_sell.price
    end
    return h, base_currency
  end
  def validate_operation(pass)
    if BCrypt::Password.new(pass) == ENV["CPTOP_RESULT"]
      return true
    end
      return false
  end
  
  def captcha(x)
    parameters = {'secret' => ENV["CAPTCHA_KEY"], 'response' => x}
    x = Net::HTTP.post_form(URI.parse('https://www.google.com/recaptcha/api/siteverify'), parameters)
    hash = JSON.parse(x.body)
    hash
  end
  def block_address(moeda)
    if moeda == 'btc'
      url = "https://btc.blockr.io/tx/info/"
    end
    if moeda == 'ltc'
      url = "https://chain.so/tx/LTC/"
    end
    url
  end
  def balance_btc_coinbase #função obsoleta
        client = Coinbase::Wallet::Client.new(api_key: ENV["COINBASE_KEY"], api_secret: ENV["COINBASE_SECRET"])
        client.accounts.each do |account|
            balance = account.balance
            #puts "#{account.name}: #{balance.amount} #{balance.currency}"
            #puts account.transactions
            if account.name == current_user.username + '@cptcambio.com'
                return String(BigDecimal(balance.amount,8)) + " "
            end
        end
    return 'Erro! solicite novo endereço '
  end
  def parabenizar_ganho(user)
        string_body = ""
        string_body << "Olá "
        string_body << user.first_name.capitalize + " " + user.last_name.capitalize
        string_body << "<br>"
        string_body << "Obrigado por utilizar nossos serviços!<br> Gostaríamos de parabenizá-lo(a) por ter jogado e ganhado em nossa loteria!!<br>"
        string_body << "\n"
        string_body << "Faça login em nosso site para verificar e/ou transferir o valor ganho."
        
        from = Email.new(email: 'no-reply@cptcambio.com')
        subject = 'Loterias CPT Cambio'
        to = Email.new(email: user.email)
        content = Content.new(type: 'text/html', value: string_body)
        mail = Mail.new(from, subject, to, content)
    
        sg = SendGrid::API.new(api_key: ENV['SENDGRID_API_KEY'])
        response = sg.client.mail._("send").post(request_body: mail.to_json)
        puts 'email enviado aqui'
        puts response.status_code
        puts response.body
        puts response.headers
    
  end
  def confirmar_email(user)
    string_body = ""
    string_body << "Olá "
    string_body << user.first_name.capitalize + " " + user.last_name.capitalize
    string_body << "<br>"
    string_body << "Obrigado por se registrar!<br> Você esta prestes a realizar compras de bitcoin e litecoins com a melhor facilidade e praticidade!<br> Tendo também acesso a todos os nossos serviços integrados de loteria, para mais detalhes, confirme seu email e confira! <br>"
    string_body << "\n"
    string_body << ("Confirme seu email clicando no link: <a href='" + ENV["LOCAL_URL"] + "/confirmation?id=" + user.confirm_token.to_s + "'> Confirmar </a>")
    
    from = Email.new(email: 'No-reply@cptcambio.com')
    subject = 'Confirmação de registro Cripto Cambio'
    to = Email.new(email: user.email)
    content = Content.new(type: 'text/html', value: string_body)
    mail = Mail.new(from, subject, to, content)

    sg = SendGrid::API.new(api_key: ENV['SENDGRID_API_KEY'])
    response = sg.client.mail._("send").post(request_body: mail.to_json)
    puts 'email enviado aqui'
    puts response.status_code
    puts response.body
    puts response.headers

  end
  def config_block #função obsoleta
    @ltc_pin = ENV["BLOCK_KEY_LTC"] 
    @btc_pin = ENV["BLOCK_KEY_BTC"]
    @pin = 'ignezconha'
    @ltc_address = '3BzasVQdbaa8s76vEfGoQRTU5jmbrfgM4B' #'2N4NyoMF6dx2UaueReFmRbHcYi5JvgumS3P'
    @btc_address = '32rcoqy2RGWybkpbfEHyXpryzBLx7LLBTF' #'2MxtY8jatyCQsXvthjy49GyQoeomtvBoTav'
    @network = 'BTC' #usada no chain.so
    @network_ltc = 'LTC'
  end
  
  def limite_compra_btc
    config_block
    balance = 0
    #client = Coinbase::Wallet::Client.new(api_key: ENV["COINBASE_KEY"], api_secret: ENV["COINBASE_SECRET"])
    #client.accounts.each do |account|
    #  if account.name == "cpt_vendas"
    #    balance = account.balance
    #  end
    #end
    limite_compra = 1
    limite_compra
  end
  def consulta_saldo_cripto(moeda,endereco)
    # moeda pode ser: ltc, btc, dgc
    #utilização de API blockr.io, todos os storages serão dela 25/07/2017
    key = Storage.key_push(moeda)
    BlockIo.set_options :api_key=> key, :pin => ENV["BLOCK_IO_PIN"], :version => 2
    balance_hash = BlockIo.get_address_balance :addresses => endereco
    return BigDecimal(balance_hash["data"]["available_balance"],8)
    sleep 1
  end
  def limite_compra_ltc
    config_block
    url_r = 'http://ltc.blockr.io/api/v1/address/info/' + @ltc_address
    uri_r = URI(url_r)
    response_r = Net::HTTP.get(uri_r)
    hash = JSON.parse(response_r)
    limite_compra = BigDecimal(String(hash["data"]["balance"])).div(2,8)
    limite_compra
  end
  
  def calcular_metodos
    parameters = {'secret' => ENV["CAPTCHA_KEY"], 'response' => params["g-recaptcha-response"]}
    x = Net::HTTP.post_form(URI.parse('https://www.google.com/recaptcha/api/siteverify'), parameters)
    hash = JSON.parse(x.body)
    if hash["success"] != true
      @captcha = false
      respond_to do | format |  
        format.js {render :layout => false}  
      end
      return
    elsif hash["success"] == true
      @captcha = true
    end
    @zero = false
    @product = Shoppe::Product.root.find_by_permalink(params['calculo']['permalink'])
    if (BigDecimal(params['calculo']['volume'].sub!(',','.'),8) <= 0) 
      @zero = true  
    end
    if BigDecimal(params['calculo']['volume'],8) <= 0.0001
      @zero = true
    end
    if params['calculo']['moeda'] == 'btc'
      a = Bitcoin.valid_address? params['calculo']['address']
      #@warning = true
      if  a == false
        @warning = false
      elsif a == true
        @warning = true
      end
      
      @carteira = params['calculo']['address']
      @desejado = BigDecimal((params['calculo']['volume'].sub(',','.')),8)
      @limit = limite_compra_btc
      @currency = 'BTC'
      @render = true
      if BigDecimal(limite_compra_btc,8) <= BigDecimal(@desejado,8)
        @limite = true
        @preco_pagseguro = String(bitcoin_para_real(@limit)) + ' BRL'
      else
        @preco_pagseguro = String(bitcoin_para_real(params['calculo']['volume'])) + ' BRL'
      end
      respond_to do | format |  
        format.js {render :layout => false}
      end
      
    end
    if params['calculo']['moeda'] == 'ltc' #ofertas de pgto para LITECOINS
      #@warning = true #Sem validação de enderaço
      a = params['calculo']['address'].match(/^L[a-km-zA-HJ-NP-Z1-9]{26,33}$/)
      if  a == nil
        @warning = false
      elsif a != nil
        @warning = true
      end
      ltc_real = litecoin_para_real
      decimal = BigDecimal(params['calculo']['volume'],5)
      
      btc_ltc = litecoin_para_bitcoin
      
      @carteira = params['calculo']['address']
      @desejado = BigDecimal((params['calculo']['volume'].sub(',','.')),8)
      puts 'render'
      @limit = limite_compra_ltc
      @currency = 'LTC'
      @render = true
      if BigDecimal(limite_compra_ltc,8) <= BigDecimal(@desejado,8)
          @limite = true
          x_real = BigDecimal(ltc_real,5).mult(limite_compra_ltc,5)
          @preco_pagseguro = String(x_real) + ' BRL'
          x_btc = BigDecimal(btc_ltc,7).mult(limite_compra_ltc,7)
          @preco_bitcoin = String(x_btc) + ' BTC'
      else
          x_real = BigDecimal(ltc_real,5).mult(decimal,5)
          @preco_pagseguro = String(x_real) + ' BRL'
          x_btc = BigDecimal(btc_ltc,7).mult(decimal,7)
          @preco_bitcoin = String(x_btc) + ' BTC'
      end
      #render 'store/show'
      respond_to do | format |  
        format.js {render :layout => false}  
      end
    end
  end
  
  def brl_btc(value)
    convert_url = 'https://blockchain.info/tobtc?currency=BRL&value=' + value.to_s
    convert_uri = URI(convert_url)
    response_convert = Net::HTTP.get(convert_uri)
    puts response_convert
    result = BigDecimal(response_convert).mult(0.75,7) 
    puts result
    result
  end
  def bitcoin_para_real(value)
    
    convert_url = 'https://blockchain.info/ticker'
    convert_uri = URI(convert_url)
    response_convert = Net::HTTP.get(convert_uri)
    hash = JSON.parse(response_convert)
    conversao = hash['BRL']['last'] # 1 BTC
    puts String(value) + '/' + String(conversao)
    if value == nil 
      result = BigDecimal(params['dynamic']).mult(conversao,2)
      @preco_pagseguro = result
      render 'calculos'
    end
    result = BigDecimal(value,7).mult(conversao,2)
    result = result.mult(1.25,2) #valor em real
    result
  end
  def litecoin_para_bitcoin
    convert_url = 'https://www.mercadobitcoin.net/api/ticker_litecoin/'
    convert_uri = URI(convert_url)
    response_convert = Net::HTTP.get(convert_uri)
    hash = JSON.parse(response_convert)
    conversao = hash['ticker']['high'] # 1 ltc em BRL
    resultado = BigDecimal(conversao,5).mult(1.25,5) # 1 ltc em BRL + 30%
    bitcoin_em_real = 'https://www.mercadobitcoin.net/api/ticker/'
    convert_uri2 = URI(bitcoin_em_real)
    response = Net::HTTP.get(convert_uri2)
    hash = JSON.parse(response)
    bitcoin_real = hash['ticker']['high']
    real = BigDecimal(resultado,8).div(BigDecimal(bitcoin_real,8),8)
    real 
  end
  def bitcoin_para_litecoin
    convert_url = 'https://www.mercadobitcoin.net/api/ticker/'
    convert_uri = URI(convert_url)
    response_convert = Net::HTTP.get(convert_uri)
    hash = JSON.parse(response_convert)
    conversao = hash['ticker']['high'] # 1 btc em R$
    convert_url2 = 'https://www.mercadobitcoin.net/api/ticker_litecoin/'
    convert_uri2 = URI(convert_url2)
    response_convert2 = Net::HTTP.get(convert_uri2)
    hash2 = JSON.parse(response_convert2)
    conversao2 = hash2['ticker']['high'] # 1 ltc em BRL
    resultado = BigDecimal(conversao,2).mult(1.25,2)
    real = resultado.div(BigDecimal(conversao2,2),8)
    real
  end
  def litecoin_para_x_bitcoin(valor_litecoin)
    convert_url = 'https://shapeshift.io/marketinfo/ltc_btc'
    convert_uri = URI(convert_url)
    response_convert = Net::HTTP.get(convert_uri)
    hash = JSON.parse(response_convert)
    conversao = hash['rate'] # 1 btc em ltc
    resultado = BigDecimal(conversao,5).mult(1.25,5) #valor de 1 btc em ltc no meu site
    result = BigDecimal(resultado,5).mult(valor_litecoin,5)
    result
  end
  def litecoin_para_real
    convert_url = 'https://www.mercadobitcoin.com.br/api/ticker_litecoin/'
    convert_uri = URI(convert_url)
    response_convert = Net::HTTP.get(convert_uri)
    hash = JSON.parse(response_convert)
    conversao = hash['ticker']['high'] # 1 ltc em real
    resultado = BigDecimal(conversao,2).mult(1.25,2)
    resultado
  end
  def standard_conversion(currency)
    tags = ''
    if currency == 'btc'
      
      tags << '<select multiple class="form-control"style="width:260px;line-height:60px;margin-left:25%;margin-top:-5%">'
      tags << '<option>'
      tags << 'BRL: ' + String(bitcoin_para_real(1))
      tags << '</option>'
      tags << '<option>'
      tags << 'LTC: ' + String(bitcoin_para_litecoin)
      tags << '</option>'
      tags << '</select>'
      return tags
    end
    if currency == 'ltc'
      tags << '<select multiple class="form-control" style="width:260px;line-height:60px;margin-left:25%;margin-top:-5%">'
      tags << '<option>'
      tags << 'BTC: ' + String(litecoin_para_bitcoin)
      tags << '</option>'
      tags << '<option>'
      tags << 'BRL: ' + String(litecoin_para_real)
      tags << '</option>'
      tags << '</select>'
      return tags
    end
    
  end
  def type(commit, tipo_moeda, valor_moeda)
        string = ""
        fim = false
        sum = false
        commit.each_char do |h|
            if h == '"' and fim == false
                sum = true
            end
            if sum == true and h != '"' and h != "="
                string << h
                fim = true
            end
            
            if h == '=' and fim == true
                
                sum = false
            end
        end
        dados = Array.new
        if string == 'pagseguro'
            moeda = 'BRL'
            dados[0] = moeda
            dados[2] = 'pagseguro'  
            if tipo_moeda == 'btc'
              dados[1] = bitcoin_para_real(valor_moeda) #quanto devo pagar em real
            end
            if tipo_moeda == 'ltc'
              b = litecoin_para_real
              decimal = BigDecimal(params['pagamento']['volume'],5)
              x_litecoin = BigDecimal(b,5).mult(decimal,5)
              dados[1] = x_litecoin
            end
        end
        if string == 'paypal'
          moeda = 'BRL'
          dados[0] = moeda
          dados[2] = 'paypal'
          if tipo_moeda == 'btc'
            dados[1] = bitcoin_para_real(valor_moeda)
          end
          if tipo_moeda == 'ltc'
              b = litecoin_para_real
              decimal = BigDecimal(params['pagamento']['volume'],5)
              x_litecoin = BigDecimal(b,5).mult(decimal,5)
              dados[1] = x_litecoin
          end
          puts 'pagamento no paypal'
          puts dados[1]
          puts dados[2]
          puts dados[0]
        end
        if string == 'bitcoin'
          moeda = 'BTC'
          dados[0] = moeda
          if tipo_moeda == 'ltc'
            puts 'compra de litecoins com bitcoin'
            decimal = BigDecimal(params['pagamento']['volume'],5)
            btc_ltc = litecoin_para_bitcoin
            x_btc = BigDecimal(btc_ltc,7).mult(decimal,7)
            dados[1] = x_btc
          end
        end
        if string == 'litecoin'
          moeda = 'LTC'
          dados[0] = moeda
          if tipo_moeda =='btc'
            puts 'compra de bitcoins com litecoins'
          end
        end
        dados
  end
  def wich_status(x)
    if x == '1'
      # 	Aguardando pagamento: o comprador iniciou a transação, mas até o momento o PagSeguro não recebeu nenhuma informação sobre o pagamento.
    end
    if x == '2'
      # Em análise: o comprador optou por pagar com um cartão de crédito e o PagSeguro está analisando o risco da transação. 
    end
    if x == '3'
      # Paga: a transação foi paga pelo comprador e o PagSeguro já recebeu uma confirmação da instituição financeira responsável pelo processamento. 
      return '3'
    end
    if x == '4'
      # Disponível: a transação foi paga e chegou ao final de seu prazo de liberação sem ter sido retornada e sem que haja nenhuma disputa aberta. 
    end
    if x == '5'
      # Em disputa: o comprador, dentro do prazo de liberação da transação, abriu uma disputa. 
    end
    if x == '6'
      # Devolvida: o valor da transação foi devolvido para o comprador. 
    end
    if x == '7'
      # Cancelada: a transação foi cancelada sem ter sido finalizada. 
    end
    if x == '8'
      # Debitado: o valor da transação foi devolvido para o comprador. 
    end
    if x == '9'
      # Retenção temporária: o comprador contestou o pagamento junto à operadora do cartão de crédito ou abriu uma demanda judicial ou administrativa (Procon). 
    end
    
    
  end
  def cors_set_access_control_headers
    headers['Access-Control-Allow-Origin'] = '*'
    headers['Access-Control-Allow-Methods'] = 'POST'
    headers['Access-Control-Allow-Headers'] = '*'
    headers['Access-Control-Request-Method'] = 'pgseguro'
    headers['Access-Control-Max-Age'] = "1728000"
  end
  def params_post
    result = "'email' => 'ricardo.malafaia1994@gmail.com', 'token' => '95112EE828D94278BD394E91C4388F20', "
    itens = ""
    order = Shoppe::Order.find(current_order.id)
    order.order_items.each do |item|
      id = id + 1
      itens = itens + '"itemId' + id.to_s + '" => "' + id.to_s + '", ' + '"itemDescription"' + id.to_s + '" => "' + (item.ordered_item.full_name).to_s + '", ' + '"itemAmount' + id.to_s + '" => "' + (item.sub_total).to_s + '", '  + '"itemQuantity' + id.to_s + '" => "' + (item.quantity).to_s + '", '
    end
    result = result + itens + "'reference' => 'REF1234', 'senderName' => '" + username.to_s + "', 'senderEmail' => '" + useremail.to_s + "', 'shippingAddressStreet' =>  '" + params["pagamento"]["rua"].to_s + "',  'shippingAddressNumber' =>  '" + params["pagamento"]["numero"] + "' , 'shippingAddressComplement' => '" + params["pagamento"]["complemento"] + "', 'shippingAddressDistrict' => '" + params["pagamento"]["bairro"] + "', 'shippingAddressPostalCode' => '"+ params["pagamento"]["postcode"] + "', 'shippingAddressCity' => '" + params["pagamento"]["cidade"] + "', 'shippingAddressState' => '" + params["pagamento"]["estado"] +"', 'shippingAddressCountry' => '" + params["pagamento"]["pais"] + "'"
    puts result
    result
  end
  def itens_string
    id = 0
    string = ""
    order = Shoppe::Order.find(current_order.id)
    order.order_items.each do |item|
      id = id + 1
      string = string + '\&itemId' + id.to_s + '=' + id.to_s + '\&itemDescription' + id.to_s + '=' + (item.ordered_item.full_name).to_s + '&itemAmount' + id.to_s + '=' + (item.sub_total).to_s + '\&itemQuantity' + id.to_s + '=' + (item.quantity).to_s 
    end
    string
  end
  def current_user 
    @current_user ||= Usuario.find(session[:user_id]) if session[:user_id] 
  end
  def require_user 
    redirect_to '/login' unless current_user 
  end
  def require_wallet
    user = current_user
    if user.bitcoin != nil or user.litecoin != nil 
      
    else
      @messages = "Você precisa ter, no mínimo, 1 carteira vinculada a sua conta para acessar essa sessão. Você pode solicitar no menu 'Inicio'<br> <a href='/'>Voltar</a>"
    end
    render '/sessions/loginerror' unless (user.bitcoin != nil or user.litecoin != nil)
  end
  def require_admin
    @messages = 'Esta ação necessita permissão administrativa.'
    render 'sessions/loginerror' unless is_admin?
  end
  
  def require_logout
    redirect_to '/' if current_user
  end
  
  def useremail
    if @current_user == nil
      current_user
      @current_user.email
    else
      @current_user.email
    end
  end
  def username
    if @current_user == nil
      current_user
      @current_user.username
    else
      @current_user.username
    end
  end
  def moeda(string)
    if string == "BTCTEST"
      return "฿T"
    end
    if string == "LTCTEST"
      return " ŁT"
    end
    if string == "BTC"
      return " ฿"
    end
    if string == "LTC"
      return " Ł"
    end
  end
  private
  def current_order
    @current_order ||= begin
      if has_order?
        @current_order
      else
        order = Shoppe::Order.create(:ip_address => request.ip)
        session[:order_id] = order.id
        order
      end
    end
  end
  def is_admin?
    user = current_user
    if user.salt == 'admin'
      true
    else
      false
    end
  end
  def has_order?
    !!(
      session[:order_id] &&
      @current_order = Shoppe::Order.includes(:order_items => :ordered_item).find_by_id(session[:order_id])
    )
  end
  def convert_bitcoin(valor)
    string = 'https://blockchain.info/tobtc?currency=BRL&value=' + valor.to_s
    uri = URI(string)
    response = Net::HTTP.get(uri)
    response
  end
  def archive_wallet(address)
    url = 'https://block.io/api/v2/archive_addresses/?api_key=ac35-6ff5-e103-d1c3&addresses=' + address
    uri = URI(url)
    response = Net::HTTP.get(uri)
    hash = JSON.parse(response)
    puts hash
  end
  def test_post
    puts "houve um post aqui"
  end
end
