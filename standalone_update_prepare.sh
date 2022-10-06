#!/usr/bin/env bash

set -o errexit

readonly STANDALONE_DIR="/root/standalone"
readonly STANDALONE_CONFIG_DIR="$STANDALONE_DIR/.config"
readonly STANDALONE_BACKUP="$STANDALONE_DIR-backup-$(date +%F)"

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
    echo "Необходимо передать путь к файлу 'prepare.config'."
    echo "Пример команды для запуска скрипта подготовки к обновлению:\n./standalone_update_prepare.sh /root/prepare.config"
    exit 1
fi

# Проверка наличия файла 'prepare.config', содержащий URL-ссылки на дистрибутив и конфигурационный файл
function check_config() {
    if [[ -z "$BUILD_URL" ]]; then
        echo "Скрипт ожидает URL-ссылку на дистрибутив в 'prepare.config' в строке BUILD_URL="
        exit 1
    fi
    if [[ -z "$CONFIG_URL" ]]; then
        echo "Скрипт ожидает URL-ссылку на конфигурационный файл в 'prepare.config' в строке CONFIG_URL="
        exit 1
    fi
}

# Бэкап старой версии дистрибутива
function standalone_backup() {
    if [ ! -d "$STANDALONE_BACKUP" ]; then
        mv "$STANDALONE_DIR" "$STANDALONE_BACKUP"
        echo "Backup директории $STANDALONE_DIR выполнен."
    else
        echo "Backup директории $STANDALONE_DIR был выполнен ранее."
    fi
}

# Проверка свободного пространства на master
function check_freespace_on_master() {
    readonly REQUIRED_UPDATE=8
    FREE_SPACE=$(expr $(df -m / | awk '{print $4}' | tail +2) / 1024) #преобразуем из Мегабайты в Гигабайты
    if [ "$FREE_SPACE" \< "$REQUIRED_UPDATE" ]; then
        echo "Для обновления требуется не менее $REQUIRED_UPDATE G свободного дискового пространства."
        echo "Cейчас доступно $FREE_SPACE G. Продолжить подготовку к обновлению? (yes/no)"
        read -r confirmation
        if [ "$confirmation" == 'no' ]; then
            echo "Подготовка к обновлению отменена."
            exit 0
        fi
    fi
}

# Скачивание и распаковка дистрибутива и слоя совместимости
function download_build_and_compatibility() {
    echo "Выполняется скачивание дистрибутива:"
    wget "$BUILD_URL" -O "$STANDALONE_DIR".tar.gz
    echo "Скачивание дистрибутива выполнено."

    tar -xvhf "$STANDALONE_DIR".tar.gz
    echo "Распаковка дистрибутива выполнена."

    echo "Выполняется скачивание конфигурационного файла:"
    wget "$CONFIG_URL" -O /root/config.tar.gz
    echo "Скачивание конфигурационного файла выполнено."

    tar -xvhf /root/config.tar.gz -C "$STANDALONE_DIR"
    echo "Распаковка конфигурационного файла выполнена."
}

#Копирование файла config из backup с дистрибутивом в новый 
function copy_config() {
    if [[ ! -f "$STANDALONE_BACKUP"/.config/config ]]; then
        echo "Конфигурационный файл $STANDALONE_BACKUP не найден."
        echo "Подготовка к обновлению прекращена."
        exit 1
    fi
    cp "$STANDALONE_BACKUP"/.config/config "$STANDALONE_CONFIG_DIR"/config
    echo "Копирование конфигурационного файла в директорию $STANDALONE_CONFIG_DIR выполнено."   
}

# Копирование файлов installer.pem, installkey.pem из backup с дистрибутивом в новый
function copy_installer_user_key() { 
    if [[ -f "$STANDALONE_BACKUP"/.config/installer.pem ]]; then
        cp "$STANDALONE_BACKUP"/.config/installer.pem "$STANDALONE_CONFIG_DIR"/installer.pem
        echo "Выполнено копирование installer.pem в $STANDALONE_CONFIG_DIR"
        return
    fi

    if [[ -f "$STANDALONE_BACKUP"/.config/installkey.pem ]]; then
        cp "$STANDALONE_BACKUP"/.config/installkey.pem "$STANDALONE_CONFIG_DIR"/installkey.pem
        echo "Выполнено копирование installkey.pem в $STANDALONE_CONFIG_DIR"
        return
    fi    
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
        | tee "$STANDALONE_CONFIG_DIR"/tls-cert.pem > /dev/null
    kubectl -n standalone get secret "$TLS_SECRET_NAME" -o jsonpath='{.data.tls\.key}' \
        | base64 -d \
        | tee "$STANDALONE_CONFIG_DIR"/tls-key.pem > /dev/null
    # дополнить конфиг-файл путями до сертификатов
    printf "\nTLS_CERTIFICATE_FILE=%q\nTLS_CERTIFICATE_KEY_FILE=%q\n" "tls-cert.pem" "tls-key.pem" \
        | tee -a "$STANDALONE_CONFIG_DIR"/config
    echo "Информация о Custom certificate сохранена в файл $STANDALONE_CONFIG_DIR/config"
}

# Копирование секретов smtp-сервера в случае K8S 1.19 и выше
function try_get_mail_smpt_parameters() {
    readonly K8S_VERSION_MAJOR=1
    readonly K8S_VERSION_MINOR=19
    if [ $(kubectl version -o json | jq '.serverVersion.major') \> "$K8S_VERSION_MAJOR" ] || [ $(kubectl version -o json | jq '.serverVersion.minor') \> "$K8S_VERSION_MINOR" ]; then
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
        | tee -a "$STANDALONE_CONFIG_DIR"/config 
    echo "Учетные данные smtp-сервера сохранены в файл $STANDALONE_CONFIG_DIR/config"
}

# Сообщения, после подготовки к обновлению
function messages_after_prepare() {
    echo "Подготовка к обновлению standalone СДО iSpring Learn завершена."
    echo "Для запуска обновления выполните следующие шаги:\n1. Выполните команду screen\n2. В screen-сессий выполните cd $STANDALONE_DIR\n3. Запустите скрипт обновления install.sh с записью обновления в лог-файл: ./install.sh 2>&1 | tee install.log"
}

main() {
    PREPARE_CONFIG=$1
    source "$PREPARE_CONFIG"

    check_config
    standalone_backup
    check_freespace_on_master
    download_build_and_compatibility
    copy_config
    copy_installer_user_key
    install_jq
    try_get_custom_certificate
    try_get_mail_smpt_parameters
    messages_after_prepare
}
main $1