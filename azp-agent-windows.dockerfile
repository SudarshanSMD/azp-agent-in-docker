FROM mcr.microsoft.com/windows/servercore:ltsc2022

WORKDIR /azp/

COPY ./start_with_spn.ps1 ./

CMD powershell .\start_with_spn.ps1