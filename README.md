Особенности:
1. Все работы выполняются на master-ноде с правами root или sudo su.
2. В случае ошибок или замечании необходимо обратиться к инженеру iSpring на support@ispring.ru с темой письма "Обновление standalone версии iSpring Learn. <Название компании>".

Инструкция по использованию скрипта:
1. Получить скрипт "standalone_update_prepare.sh"
Для этого залогиниться на master-ноде и получить скрипт в директорию /root, выполнив команду:
```
wget https://raw.githubusercontent.com/ispringtech/on-prem-learn-scripts/main/standalone_update_prepare.sh -O standalone_update_prepare.sh; chmod +x standalone_update_prepare.sh
```
2. Получить от инженера iSpring файл "prepare.config", содержащий уникальные URL-ссылки на дистрибутив и конфигурационный файл.
Разместить полученный файл в директорию /root

3. Выполнение скрипта.
Запустить скрипт "standalone_update_prepare.sh", передав путь к файлу "prepare.config": 
   ```
   ./standalone_update_prepare.sh /root/prepare.config
   ```