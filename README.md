## Zabbix Speedtest With Zabbix Trapper(Sender)

Este script coleta dados de velocidade de internet usando o speedtest-cli e envia as métricas para o Zabbix.

**Necessidades:**

* **Zabbix Agent configurado:** O agente Zabbix deve estar instalado e funcionando corretamente na máquina alvo.
* **Zabbix Sender instalado:** O Zabbix Sender é necessário para enviar as métricas para o servidor Zabbix.
* **jq instalado:** O jq é usado para processar a saída do speedtest-cli.
* **speedtest-cli instalado:** O speedtest-cli é usado para realizar os testes de velocidade.
* **o Arquivo run_and_send_speedtest_metrics.sh:** O script que coleta os dados de velocidade e os envia para o Zabbix deve está na pasta /etc/zabbix/zabbix_agentd.d/run_and_send_speedtest_metrics.sh .

**Instalação do speedtest-cli no Rocky Linux:**

Caso o speedtest-cli não esteja instalado, siga estes passos:

1. Execute o seguinte comando para adicionar o repositório do speedtest-cli:

```bash
curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.rpm.sh | sudo bash
```

2. Instale o speedtest-cli usando o yum:

```bash
sudo yum install speedtest
```

**Configuração:**

1. **Permissões do script:**

   Execute o seguinte comando para dar permissão de execução ao script:

   ```bash
   sudo chmod +x /etc/zabbix/zabbix_agentd.d/run_and_send_speedtest_metrics.sh
   ```

2. **Crontab:**

   Verifique se o crontab está configurado para executar o script a cada 4 horas.
   ```bash
   sudo crontab -l
   ```

   Para editar o crontab, execute:

   ```bash
   sudo crontab -e
   ```
   Se não estiver, adicione a seguinte linha ao crontab:
   ```bash
   0 1,5,9,13,17,21 * * * /etc/zabbix/zabbix_agentd.d/run_and_send_speedtest_metrics.sh > /var/log/zabbix_speedtest_sender.log 2>&1
   ```



**Observações:**

* O script envia as seguintes métricas para o Zabbix: download, upload e ping.
* As métricas são enviadas com o prefixo "speedtest.".
* O log do script é gravado em `/var/log/zabbix_speedtest_sender.log`.
