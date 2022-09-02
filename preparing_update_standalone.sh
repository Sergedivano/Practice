#!/usr/bin/env bash

set -o errexit

readonly MAINPATH=/root/standalone
readonly MAINPATH_CONFIG="$MAINPATH"/.config
readonly MAINPATH_BACKUP="$MAINPATH"-backup-$(date +%F)

# ПРОВЕРКА ПРАВ АДМИНА
ROOT_UID=0
if [ "$UID" != "$ROOT_UID" ]; then
    echo "У вас недостаточно прав для запуска этого скрипта. Для продолжения авторизоваться с правами root или использовать sudo su."
    exit 1
fi

# Проверка установленного standalone
if [ $(kubectl get namespaces | grep -c -i standalone) != 1 ] ; then
    echo "Серверная версии СДО iSpring Learn не найдена. Обратитесь в iSpring Support support@ispring.ru."
    exit 1
fi

if [[ -z "$1" ]]; then
    echo "Необходимо передать путь к файлу 'preparing_config'."
    echo "Пример команды для запуска скрипта подготовки к обновлению:
    ./preparing_update_standalone.sh /root/preparing_config"
    exit 1
fi

# Проверка наличия файла 'preparing_config', содержащий URL-ссылки на дистрибутив и конфигурационный файл
function check_preparing_config() {
    if [[ -z "$BUILD_URL" ]]; then
        echo "Скрипт ожидает URL-ссылку на дистрибутив в 'preparing_config' в строке BUILD_URL="
        exit 1
    fi
    if [[ -z "$CONFIG_URL" ]]; then
        echo "Скрипт ожидает URL-ссылку на конфигурационный файл в 'preparing_config' в строке CONFIG_URL="
        exit 1
    fi
}

# Бэкап старой версии дистрибутива
function standalone_backup() {
    STANDALONE_BACKUP_DIR="/root/standalone-backup-$(date +%F)"
    if [ ! -d "$STANDALONE_BACKUP_DIR" ]; then
        mv "$MAINPATH" "$STANDALONE_BACKUP_DIR"
        echo "Backup директории $MAINPATH выполнен."
    else
        echo "Backup директории $MAINPATH был выполнен ранее."
    fi
}

# Проверка свободного пространства на master
function check_freespace_on_master() {
    readonly CAPACITY_UPDATE=8
    FREE_SPACE=$(expr $(df -m / | awk '{print $4}' | tail +2) / 1024) #преобразуем из Мегабайты в Гигабайты
    if [ "$FREE_SPACE" \> "$CAPACITY_UPDATE" ]; then
        echo "Для обновления требуется не менее 8 G свободного дискового пространства."
        echo "Cейчас доступно $FREE_SPACE G. Продолжить подготовку к обновлению? (yes/no)"
        read -r confirmation
        if [ "$confirmation" == 'no' ]; then
            echo "Подготовка к обновлению отменена."
            exit 0
        fi
    fi
}

# Скачивание и распаковка дистрибутива и слоя совместимости с копированием в директорию /root/standalone
function download_tar_distribute_config() {
    cd /root
    wget "$BUILD_URL" -O standalone.tar.gz
        echo "Скачивание дистрибутива выполнено."
    tar -xvhf standalone.tar.gz
        echo "Распаковка дистрибутива выполнена."
    wget "$CONFIG_URL" -O config.tar.gz
        echo "Скачивание конфигурационного файла выполнено."
    tar -xvhf config.tar.gz -C standalone
        echo "Распаковка конфигурационного файла выполнена."
    #Копирование файла config из старой папки с дистрибутивом в новый  
    cp "$MAINPATH_BACKUP"/.config/config "$MAINPATH_CONFIG"/config
        echo "Копирование конфигурационного файла в директорию $MAINPATH_CONFIG выполнено." 
}

# Копирование файлов installer.pem, installer.pem.pub из старой папки с дистрибутивом в новый 
function copy_installer() {
    cd /root
    #SEARCHER_INSTALLER="$MAINPATH_BACKUP"/.config/install*.pem*
    INSTALLER_PEM="$MAINPATH_BACKUP"/.config/installer.pem
    INSTALLER_PEM_PUB="$MAINPATH_BACKUP"/.config/installer.pem.pub
    #if [[ -z "$SEARCHER_INSTALLER" ]]; then
    if [[ ! -f "$INSTALLER_PEM" ]]; then
        return
    fi        
        echo "$INSTALLER_PEM найден. Будет выполнено копирование."
        cp "$MAINPATH_BACKUP"/.config/installer.pem "$MAINPATH_CONFIG"/installer.pem
        echo "Копирование выполнено"

    if [[ ! -f "$INSTALLER_PEM_PUB" ]]; then
        return
    fi    
        echo "$INSTALLER_PEM_PUB найден. Будет выполнено копирование."
        cp "$MAINPATH_BACKUP"/.config/installer.pem.pub "$MAINPATH_CONFIG"/installer.pem.pub   
        echo "Копирование выполнено"  
}

# Копирование файлов installkey.pem, installkey.pem.pub из старой папки с дистрибутивом в новый
function copy_installkey() { 
    cd /root
    INSTALLKEY_PEM="$MAINPATH_BACKUP"/.config/installkey.pem
    INSTALLKEY_PEM_PUB="$MAINPATH_BACKUP"/.config/installkey.pem.pub
    if [[ ! -f "$INSTALLKEY_PEM" ]]; then
         return
    fi
        echo "$INSTALLKEY_PEM найден. Будет выполнено копирование."
        cp "$MAINPATH_BACKUP"/.config/installkey.pem "$MAINPATH_CONFIG"/installkey.pem
        echo "Копирование выполнено"

    if [[ ! -f "$INSTALLKEY_PEM_PUB" ]]; then
         return
    fi
        echo "$INSTALLKEY_PEM_PUB найден. Будет выполнено копирование."
        cp "$MAINPATH_BACKUP"/.config/installkey.pem.pub "$MAINPATH_CONFIG"/installkey.pem.pub
        echo "Копирование выполнено"
}

# Установка jq
function install_jq() {
    if [[ -z "$(command -v jq)" ]]; then
        echo "Программа 'jq' не найдена. Будет выполнена установка 'jq'."
        apt update && apt install -y jq
        echo "Установка 'jq' выполнена."
    fi
}

# Проверка кастомных сертификатов
function try_get_custom_certificate() {
    TLS_SECRET_NAME=$(kubectl -n standalone get ingress learn-ingress -o jsonpath='{.spec.tls[0].secretName}')
    # проверить центр сертификации, который выдал текущий сертификат
    openssl x509 -in <(kubectl -n standalone get secret "$TLS_SECRET_NAME" -o jsonpath='{.data.tls\.crt}' | base64 -d) \
        -issuer -noout \
        | (grep -i 'CN = iSpring-IssuingCA' || echo "Custom certificate найден.")
    # в случае кастомного сертификата сохранить сертификат в файл
    kubectl -n standalone get secret "$TLS_SECRET_NAME" -o jsonpath='{.data.tls\.crt}' \
        | base64 -d \
        | tee "$MAINPATH_CONFIG"/tls-cert.pem > /dev/null
    kubectl -n standalone get secret "$TLS_SECRET_NAME" -o jsonpath='{.data.tls\.key}' \
        | base64 -d \
        | tee "$MAINPATH_CONFIG"/tls-key.pem > /dev/null
    # дополнить конфиг-файл путями до сертификатов
    printf "\nTLS_CERTIFICATE_FILE=%q\nTLS_CERTIFICATE_KEY_FILE=%q\n" "tls-cert.pem" "tls-key.pem" \
        | tee -a "$MAINPATH_CONFIG"/config
        echo "Информация о Custom certificate сохранена в файл $MAINPATH_CONFIG/config"
}

# Копирование секретов smtp-сервера в случае K8S 1.19 и выше
function try_get_mail_smpt_parameters() {
    readonly K8S_VERSION_MAJOR=1
    readonly K8S_VERSION_MINOR=19
    if [ $(kubectl version -o json | jq '.serverVersion.major') != "$K8S_VERSION_MAJOR" ] && [ $(kubectl version -o json | jq '.serverVersion.minor') \< "$K8S_VERSION_MINOR" ]; then
        return
    fi    
    LEARN_APP_POD_NAME=$(kubectl -n standalone get pod --field-selector=status.phase=Running -l app=learn,tier=frontend -o jsonpath='{.items[0].metadata.name}')
    LEARN_APP_SECRET_NAME=$(kubectl -n standalone get pod "$LEARN_APP_POD_NAME" -o jsonpath='{.spec.containers[0].envFrom}' | jq -r '.[] | select(.secretRef.name | test("learn-app-env-secret.*")?) | .secretRef.name')
    # из секрета получаем логин от smtp сервера
    MAIL_SMTP_USERNAME=$(kubectl -n standalone get secret "$LEARN_APP_SECRET_NAME" -o jsonpath='{.data.PARAMETERS_MAIL_SMTP_USERNAME}' | base64 -d)
    # из секрета получаем пароль от smtp сервера 
    MAIL_SMTP_PASSWORD=$(kubectl -n standalone get secret "$LEARN_APP_SECRET_NAME" -o jsonpath='{.data.PARAMETERS_MAIL_SMTP_PASSWORD}' | base64 -d)
    # дополняем файл настроек с кредами к почтовику
    printf "\nPARAMETERS_MAIL_SMTP_USERNAME=%q\nPARAMETERS_MAIL_SMTP_PASSWORD=%q\n" "$MAIL_SMTP_USERNAME" "$MAIL_SMTP_PASSWORD" \
        | tee -a "$MAINPATH_CONFIG"/config > /dev/null
    echo "Учетные данные smtp-сервера сохранены в файл $MAINPATH_CONFIG/config"    
}

# Сообщения, после подготовки к обновлению
function messages_after_preparing() {
        echo "Подготовка к обновлению standalone СДО iSpring Learn завершена."
        echo "Для запуска обновления выполните следующие шаги:
        1. Выполните команду screen
        2. В screen-сессий выполните cd $MAINPATH
        3. Запустите скрипт обновления install.sh с записью обновления в лог-файл: ./install.sh 2>&1 | tee install.log"
}

main() {
    PREPARING_CONFIG=$1
    source "$PREPARING_CONFIG"
    check_preparing_config
    standalone_backup
    check_freespace_on_master
    download_tar_distribute_config
    copy_installer
    copy_installkey
    install_jq
    try_get_custom_certificate
    try_get_mail_smpt_parameters
    messages_after_preparing
}

main $1