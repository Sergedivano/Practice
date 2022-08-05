#!/usr/bin/env bash
set -o errexit

# ПРОВЕРКА ПРАВ АДМИНА тестить под разными пользователями и EUID и UID //Проверено на Stage
if [ "$UID" -ne "$ROOT_UID" ]; then 
  echo "Для продолжения необходимы права root: sudo su"
  exit $E_NOTROOT
fi  

# Проверка установленного standalone //Проверено на Stage
if [ $(kubectl get namespaces | grep standalone | wc -l) < 1 ] ; then 
  echo "Серверная версии СДО iSpring Learn не найдена. Обратитесь в iSpring Support support@ispring.ru"
  exit 1
fi  

# Проверка доступа к файлу конфигурации
if [[ -z "$1" ]]; then
  echo "Необходимо передать путь к файлу конфигурации ~/путь к "
  echo "команды"
  echo "команды"
  echo "команды"

  exit 1
fi

CONFIG_FILE=$1

source "$CONFIG_FILE"

if [[ -z "$BUILD_URL" ]]; then
  echo "Скрипт ожидает URL-ссылку на дистрибутив. $BUILD_URL"
  exit 1
fi

if [[ -z "$CONFIG_URL" ]]; then
  echo "Скрипт ожидает URL-ссылку на конфигурационный файл. $CONFIG_URL"
  exit 1
fi

# Бэкап старой версии дистрибутива
function standalone_backup () {
    STANDALONE_BACKUP_DIR=~/"standalone-backup-$(date +%F)"
    if [ ! -d "$STANDALONE_BACKUP_DIR" ]; then
        mv ~/standalone "$STANDALONE_BACKUP_DIR"
        echo "Бэкап создан"
    else 
        echo "Бэкап был создан ранее"  
    fi
}

# Проверка свободного пространства на master
function free_space on master () {
    FREE_SPACE=$(expr $(df -m / | awk '{print $4}' | tail +2) / 1024) #преобразуем из Мегабайты в Гигабайты
    if [ $FREE_SPACE < 8 ]; then
        echo "Для обновления требуется не менее 8G свободного диского пространства."
        echo "Cейчас $FREE_SPACE. Продолжить подготовку к обновлению? (yes/no)"
        read -r confirmation
            if [ "$confirmation" == 'no' ]; then
                echo "Подготовка к обновлению отменена"
                exit 0
            fi   
    fi  
}

main() {
    function standalone_backup;
    function free_space on master;
    # Скачивание и распаковка дистрибутива и слоя совместимости
    cd /root
    wget '$BUILD_URL' -O standalone.tar.gz
    tar -xvhf standalone.tar.gz
    wget '$CONFIG_FILE' -O config.tar.gz
    tar -xvhf config.tar.gz -C standalone

    #Скопировать файл config из старой папки с дистрибутивом в новый  
    cp ~/standalone-backup-$(date +%F)/.config/config ~/standalone/.config/config

}
main;





# КОПИРОВАНИЕ КАСТОМНЫХ СЕРТИФИКАТОВ
  TLS_SECRET_NAME=$(sudo kubectl -n standalone get ingress learn-ingress -o jsonpath='{.spec.tls[0].secretName}')
    # проверить центр сертификации, который выдал текущий сертификат
      openssl x509 -in <(sudo kubectl -n standalone get secret "$TLS_SECRET_NAME" -o jsonpath='{.data.tls\.crt}' | base64 -d) \
      -issuer -noout \
      | (grep -i 'CN = iSpring-IssuingCA' || echo "Custom certificate found")
 
    # в случае кастомного сертификата сохранить сертификат в файл
      sudo kubectl -n standalone get secret "$TLS_SECRET_NAME" -o jsonpath='{.data.tls\.crt}' \
      | base64 -d \
      | tee ~/standalone/.config/tls-cert.pem > /dev/null
 
      sudo kubectl -n standalone get secret "$TLS_SECRET_NAME" -o jsonpath='{.data.tls\.key}' \
      | base64 -d \
      | tee ~/standalone/.config/tls-key.pem > /dev/null
 
    # дополнить файл настроек путями до сертификатов
      printf "\nTLS_CERTIFICATE_FILE=%q\nTLS_CERTIFICATE_KEY_FILE=%q\n" "tls-cert.pem" "tls-key.pem" \
      | tee -a ~/standalone/.config/config

# Копирование секретов smtp-сервера в случае K8S 1.19 // \> для экранирования //Проверено на Stage
if [ $(kubectl get nodes -n standalone | awk '{print $5}' | tail +4 ) \> v1.19.00 ]; then
  LEARN_APP_POD_NAME=$(kubectl -n "standalone" get pod --field-selector=status.phase=Running -l app=learn,tier=frontend -o jsonpath="{.items[0].metadata.name}")
  LEARN_APP_SECRET_NAME=$(sudo kubectl -n standalone get pod "$LEARN_APP_POD_NAME" -o jsonpath='{.spec.containers[0].envFrom}' | jq -r '.[] | select(.secretRef.name|test("learn-app-env-secret.*")?) | .secretRef.name')
  # из секрета получаем логин от smtp сервера
  MAIL_SMTP_USERNAME=$(sudo kubectl -n standalone get secret $LEARN_APP_SECRET_NAME -o jsonpath='{.data.PARAMETERS_MAIL_SMTP_USERNAME}' | base64 -d)
  # из секрета получаем пароль от smtp сервера 
  MAIL_SMTP_PASSWORD=$(sudo kubectl -n standalone get secret $LEARN_APP_SECRET_NAME -o jsonpath='{.data.PARAMETERS_MAIL_SMTP_PASSWORD}' | base64 -d)
   # дополняем файл настроек с кредами к почтовику
  printf "\nPARAMETERS_MAIL_SMTP_USERNAME=%q\nPARAMETERS_MAIL_SMTP_PASSWORD=%q\n" "$MAIL_SMTP_USERNAME" "$MAIL_SMTP_PASSWORD" \
    | tee -a ~/standalone/.config/config
else
  exit 1
fi  


echo "Подготовка к обновлению завершена."
echo "Для запуска обновления перейдите в screen и запустите скрипт установщика install.sh с записью обновления в лог файл.
screen
cd /root/standalone
./install.sh 2>&1 | tee install.log"






#if [ $(ls -l | grep standalone-backup-$(date +%F) ) == 'standalone-backup-$(date +%F)' ]; then 
#else [ $FREE_SPACE ]
 # echo "Бэкап не создан, т.к. не достаточно объема свободного диского пространства. Требуется не менее 10G, сейчас $FREE_SPACE "
#fi  
# Обработка ошибки - ` mv: cannot stat 'standalone': No such file or directory`, значит, что установка была от другого пользователя и расположена в другой директории. 
   



