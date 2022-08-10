#!/usr/bin/env bash
set -o errexit

# ПРОВЕРКА ПРАВ АДМИНА тестить под разными пользователями и EUID и UID //Проверено на Stage
if [ "$UID" -ne "$ROOT_UID" ]; then 
  echo "Для продолжения необходимы права root или введите команду: sudo su"
  exit $E_NOTROOT
fi  

# Проверка установленного standalone //Проверено на Stage
if [ $(kubectl get namespaces | grep standalone | wc -l) < 1 ] ; then 
  echo "Серверная версии СДО iSpring Learn не найдена. Обратитесь в iSpring Support support@ispring.ru"
  exit 1
fi  

# Проверка наличия файла preparing_update_url.txt, содержащий URL-ссылки на дистрибутив и конфигурационный файл
function check_preparing_file () {
if [[ -z "$1" ]]; then
  echo "Необходимо передать путь к файлу /root/standalone/preparing_update_url "
  echo "команды"
  echo "команды"
  echo "команды"
  exit 1
fi
PREPARING_FILE=$1
source "$PREPARING_FILE"
if [[ -z "$BUILD_URL" ]]; then
  echo "Скрипт ожидает URL-ссылку на дистрибутив. $BUILD_URL"
  exit 1
fi
if [[ -z "$CONFIG_URL" ]]; then
  echo "Скрипт ожидает URL-ссылку на конфигурационный файл. $CONFIG_URL"
  exit 1
fi
}

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
function free_space_on_master () {
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

# Проверка кастомных сертификатов
function check_Custom_certificate () {
    # КОПИРОВАНИЕ КАСТОМНЫХ СЕРТИФИКАТОВ
    TLS_SECRET_NAME=$(sudo kubectl -n standalone get ingress learn-ingress -o jsonpath='{.spec.tls[0].secretName}')
    # проверить центр сертификации, который выдал текущий сертификат
    openssl x509 -in <(sudo kubectl -n standalone get secret "$TLS_SECRET_NAME" -o jsonpath='{.data.tls\.crt}' | base64 -d) \
      -issuer -noout \
      | (grep -i 'CN = iSpring-IssuingCA' || echo "Custom certificate found")
 
    # в случае кастомного сертификата сохранить сертификат в файл
    kubectl -n standalone get secret "$TLS_SECRET_NAME" -o jsonpath='{.data.tls\.crt}' \
      | base64 -d \
      | tee ~/standalone/.config/tls-cert.pem > /dev/null
 
    kubectl -n standalone get secret "$TLS_SECRET_NAME" -o jsonpath='{.data.tls\.key}' \
      | base64 -d \
      | tee ~/standalone/.config/tls-key.pem > /dev/null
 
    # дополнить файл настроек путями до сертификатов
    printf "\nTLS_CERTIFICATE_FILE=%q\nTLS_CERTIFICATE_KEY_FILE=%q\n" "tls-cert.pem" "tls-key.pem" \
      | tee -a ~/standalone/.config/config
}      

main() {
    function check_preparing_file;
    function standalone_backup;
    function free_space_on_master;

    # Скачивание и распаковка дистрибутива и слоя совместимости
    cd /root
    wget '$BUILD_URL' -O standalone.tar.gz
    tar -xvhf standalone.tar.gz
    wget '$CONFIG_FILE' -O config.tar.gz
    tar -xvhf config.tar.gz -C standalone

    #Копирование файла config из старой папки с дистрибутивом в новый  
    cp ~/standalone-backup-$(date +%F)/.config/config ~/standalone/.config/config

    function check_Custom_certificate; 
}
main;

# Необходимо вывести сообщение после функции main()
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
   



