Особенности:
    1. Все работы выполняются на master-ноде с правами root или sudo su.
    2. В случае ошибок или замечании необходимо обратиться к инженеру iSpring на support@ispring.ru с темой письма "Обновление standalone версии iSpring Learn. <Название компании>".

Инструкция по использованию скрипта:
1. Получить скрипт "preparing_update_standalone.sh"
Залогиниться на master-ноде и получить скрипт в директорию /root/standalone, выполнив команду:
```
wget https://raw.githubusercontent.com/ispringtech/on-prem-learn-scripts/main/preparing_update_standalone.sh -O preparing_update_standalone.sh; chmod +x preparing_update_standalone.sh
```
2. Получить от инженера iSpring файл "preparing_update_url.txt", содержащий уникальные URL-ссылки на дистрибутив и конфигурационный файл.
   Разместить полученный файл в директорию /root/standalone

3. Выполнение скрипта.
   Запустить скрипт "preparing_update_standalone.sh" командой: 
   ```
   ./preparing_update_standalone.sh 2>&1 | tee preparing.log
   ```