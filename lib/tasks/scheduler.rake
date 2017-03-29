require 'net/http'
require 'coinbase/wallet'
require 'date' 

desc "This task is called by the Heroku scheduler add-on"
task :teste_keys, [:secret, :key, :sendgrid] => :environment do |t, chave|
    chave.with_defaults(:secret => "default_secret_value", :key => "default_keyex_value", :sendgrid => "default_sendgrid_value")
    # args[:arg1] and args[:arg2] contain the arg values, subject to the defaults
    puts chave.secret
    puts chave.key
    puts chave.sendgrid
end
#rake roll_lottery_btc[1,2,3]
task :roll_lottery_btc, [:secret, :key, :sendgrid] => :environment do |t, chave|
    chave.with_defaults(:secret => "default_secret_value", :key => "default_keyex_value", :sendgrid => "default_sendgrid_value")
    loterium = Loterium.new
    logr = "Script de loteria rodado no dia: "
    logr << Time.now.strftime("%d/%m/%y\n")
    array_carteiras = []
    array_qtd = []
    if data_sorteio = Time.now.strftime("%d") == "01"
        puts "data correta"
        tickets = Ticketbtc.all.where(:sorteavel => true)
        total_sorteavel = 0
        usuarios = []
        contador = 0
        piscina_tickets = Array.new
        tickets.each do |h|
            usuarios[contador] = h.usuario
            Integer(h.proporcao).times do
                piscina_tickets << h.usuario
            end
            total_sorteavel = Integer(total_sorteavel) + Integer(h.proporcao)
            contador = contador + 1
        end
        
        proporcoes_premios = [0.40,0.20,0.11,0.09,0.07,0.05,0.04,0.03,0.015,0.005].to_a
        proporcoes_premios.each do |k|
            premiado = rand(0...total_sorteavel)
            client = Coinbase::Wallet::Client.new(api_key: chave.key, api_secret: chave.secret)
            primary_account = client.primary_account
            client.accounts.each do |account|
                balance = primary_account.balance
                premio_string = (balance.amount * k).truncate(8).to_s
                puts "premio = #{premio_string}"
                user = Usuario.find_by_username(account.name.chomp("@cptcambio.com"))
                if user != nil and piscina_tickets != nil and premiado != nil and user.email == piscina_tickets[premiado]
                    puts 'entregar premio'
                    if piscina_tickets[premiado] != nil
                        username = account.name.chomp("@cptcambio.com")
                        user_premiado = Usuario.find_by_username(username)
                        j = Ticketbtc.all.where(:sorteavel => true,  :usuario => user_premiado.email).take
                        logr << "Enviado bitcoins aqui para o ganhador #{user_premiado.email}, no valor de #{premio_string}, para o endereço #{user_premiado.bitcoin}\n"
                        primary_account.send( :to => user_premiado.bitcoin, :amount => premio_string, :currency => 'BTC')
                        loterium.parabenizar_ganho(user_premiado, premio_string, chave.sendgrid)
                        b = Premiado.find_by_endereco(user_premiado.bitcoin) #estatísticas, para salvar todos os usuários premiados
                        if b == nil
                            b = Premiado.new
                            b.endereco = user_premiado.bitcoin
                            b.qtd_btc = premio_string
                            b.save
                        else
                            b.qtd_btc = BigDecimal(b.qtd_btc,8) + BigDecimal(premio_string,8)
                            b.save
                        end
                        j.sorteavel = false
                        j.save
                        total_sorteavel = Integer(total_sorteavel) - Integer(j.proporcao)
                        
                        piscina_tickets.reject! { |n| n == j.usuario }
                        
                    else
                        puts "sem usuários para serem sorteados"
                    end
                end
            end
        end
        j = Ticketbtc.all.where(:sorteavel => true)
        j.each do |g|
            g.sorteavel = false
            g.save
        end
        data_sorteio = Time.now.strftime("%d/%m/%Y")
        all = Loterium.all
        g = all[0]
        if g == nil
            f = Loterium.new
            f.data = data_sorteio
            f.save
        else
            a_date = Date.parse(g.data)
            b_date = a_date + 31
            g.data = b_date
            g.save
        end
        
        logr << "Sorteio realizado, todos os tickets estão não sorteáveis, aplicar nova data de sorteio.\n"
        logr << "Concluindo log.\n-------------------------\n"
    else
        logr << "Data errada, não realizar sorteio.\n"
        logr << "Concluindo log.\n-------------------------\n"
    end
    loging = loterium.montar_xml(array_carteiras,array_qtd)
    arquivo_log = File.open("./statistics/loteria.log", "a") do |j|
        j << logr
    end
end