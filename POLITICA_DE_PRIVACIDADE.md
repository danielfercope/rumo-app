# Política de Privacidade — RUMO

**Última atualização:** 22 de setembro de 2026

Esta Política de Privacidade descreve como o aplicativo **RUMO** ("o aplicativo", "nós") coleta, usa, armazena e protege os dados pessoais de seus usuários, em conformidade com a Lei Geral de Proteção de Dados Pessoais (LGPD — Lei nº 13.709/2018).

O RUMO é uma ferramenta de uso interno voltada para equipes de vendas externas (field sales), utilizada por colaboradores autorizados para prospecção comercial baseada em geolocalização.

> **Nota**: este projeto ainda não está vinculado a uma pessoa jurídica registrada. Até que isso ocorra, o responsável pelo tratamento dos dados (controlador, nos termos da LGPD) é a equipe responsável pelo desenvolvimento e operação do RUMO, através do contato indicado na seção 8. Assim que houver uma empresa formalmente constituída operando o aplicativo, esta política deve ser atualizada com a razão social e o CNPJ correspondentes.

---

## 1. Quais dados coletamos

### 1.1 Dados de cadastro
Ao criar uma conta, coletamos: nome completo, e-mail, senha (armazenada de forma criptografada pelo provedor de autenticação) e departamento/função na empresa. Caso o login seja feito via Google, recebemos também nome, e-mail e foto de perfil associados à conta Google utilizada.

### 1.2 Dados de localização (geolocalização)
Enquanto a sessão estiver ativa, o aplicativo coleta a localização GPS do dispositivo a cada 5 minutos, para fins de:
- Exibir empresas/leads no raio de atuação do usuário no mapa;
- Registrar a posição da equipe em campo (visualização em tempo real para gestão comercial);
- Manter um histórico de localizações para fins de análise de rotas e cobertura territorial.

Essa é a coleta de dado pessoal mais sensível feita pelo aplicativo, por ser contínua e vinculada à identidade do colaborador. Ela existe porque é o núcleo funcional do produto — sem ela, o aplicativo não cumpre seu propósito de prospecção geoespacial.

### 1.3 Dados de uso e diagnóstico
Utilizamos o Firebase Analytics e o Firebase Crashlytics (Google) para coletar, de forma agregada: telas visitadas, eventos de navegação, informações técnicas do dispositivo (modelo, sistema operacional) e relatórios de falhas (crashes) da aplicação. Esses dados são usados exclusivamente para melhorar a estabilidade e a experiência de uso do aplicativo.

### 1.4 Dados de empresas e leads
O aplicativo permite cadastrar e consultar dados públicos de empresas (razão social, CNPJ, endereço, segmento) obtidos junto à API EmpresaAqui, e sincronizados com o CRM HubSpot. Esses dados dizem respeito a pessoas jurídicas (empresas prospectadas), não a dados pessoais de terceiros — exceto quando um contato individual (nome, e-mail, telefone) é cadastrado manualmente no CRM pelo próprio usuário durante o processo comercial.

---

## 2. Finalidade do tratamento

Os dados descritos acima são usados para:
- Autenticar e identificar o usuário dentro do aplicativo;
- Exibir empresas e leads próximos à localização do usuário;
- Permitir à gestão comercial acompanhar a distribuição territorial da equipe de vendas;
- Sincronizar informações comerciais com o CRM (HubSpot);
- Diagnosticar e corrigir falhas técnicas do aplicativo.

Não utilizamos os dados coletados para fins publicitários, venda a terceiros, ou qualquer finalidade além das descritas nesta política.

---

## 3. Base legal (LGPD)

O tratamento dos dados de localização e cadastro se baseia na **execução de contrato de trabalho ou vínculo profissional** (art. 7º, V, LGPD), já que o rastreamento de posição é inerente à função do usuário como executivo de vendas externas em atividade. Os dados de uso/diagnóstico (Analytics/Crashlytics) se baseiam no **legítimo interesse** do desenvolvedor em manter e melhorar o aplicativo (art. 7º, IX, LGPD).

---

## 4. Com quem compartilhamos dados

| Terceiro | Dados compartilhados | Finalidade |
|---|---|---|
| Supabase (banco de dados e autenticação) | Todos os dados de cadastro e localização | Armazenamento e autenticação |
| Google / Firebase | Dados de uso, diagnóstico, e-mail (login social) | Analytics, Crashlytics, autenticação |
| HubSpot | Dados de empresas/leads e contatos comerciais inseridos pelo usuário | Gestão de CRM |
| EmpresaAqui | CNPJ consultado (dado da empresa prospectada, não pessoal do usuário) | Enriquecimento cadastral de empresas |

Nenhum desses terceiros está autorizado a usar os dados para finalidade diferente da contratada.

---

## 5. Armazenamento e segurança

Os dados são armazenados em banco de dados PostgreSQL gerenciado pelo Supabase, com autenticação obrigatória e controle de acesso por usuário. Senhas nunca são armazenadas em texto plano. Adotamos as medidas técnicas razoáveis disponíveis nas plataformas utilizadas (Supabase, Google/Firebase) para proteger os dados contra acesso não autorizado, perda ou vazamento.

## 6. Retenção dos dados

Os dados de cadastro e histórico de localização são mantidos enquanto o vínculo do usuário com a operação estiver ativo. Após o encerramento do vínculo, os dados podem ser retidos por período adicional razoável para fins de auditoria comercial, sendo posteriormente anonimizados ou eliminados mediante solicitação.

## 7. Direitos do titular dos dados

Nos termos do art. 18 da LGPD, você tem direito a, mediante solicitação:
- Confirmar a existência de tratamento dos seus dados;
- Acessar os dados que temos sobre você;
- Corrigir dados incompletos, inexatos ou desatualizados;
- Solicitar a anonimização, bloqueio ou eliminação de dados desnecessários ou excessivos;
- Solicitar a portabilidade dos dados a outro fornecedor;
- Revogar o consentimento e solicitar a eliminação dos dados tratados com base nele;
- Obter informação sobre as entidades com as quais seus dados foram compartilhados.

## 8. Contato

Para exercer os direitos acima ou tirar dúvidas sobre esta política, entre em contato: **danielfercope@gmail.com**.

## 9. Alterações nesta política

Esta política pode ser atualizada periodicamente para refletir mudanças no aplicativo ou na legislação aplicável. A data da última atualização está sempre indicada no topo deste documento.
