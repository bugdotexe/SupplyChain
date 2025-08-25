
#!/bin/bash

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'

OUTPUT_DIR="tech_results"
DB_FILE="$OUTPUT_DIR/tech.db"
mkdir -p "$OUTPUT_DIR"

WHITELIST=(                                       # Servers & Proxies
  Apache Nginx IIS Varnish Caddy Lighttpd Tomcat Traefik HAProxy OpenResty
  Squid Envoy Apache-Traffic-Server "Amazon Web Services" Akamai

  # CMS
  WordPress Drupal Joomla Magento Shopify Ghost Strapi Contentful Sitecore                        AdobeExperienceManager Kentico Umbraco PrestaShop TYPO3 ConcreteCMS                           
  # API Technologies
  Swagger OpenAPI GraphQL Apollo REST SOAP JSON-RPC XML-RPC gRPC WebSocket
  AzureAPIManagement Kong Tyk Postman LoopBack                                                    # Monitoring & Analytics
  Grafana Kibana Prometheus Splunk NewRelic Datadog Sentry Airbrake ELK                           Zabbix Nagios AppDynamics Dynatrace
                                                  # Databases & Caching                           MySQL PostgreSQL MongoDB Elasticsearch Redis Memcached Cassandra CouchDB                        SQLite Oracle MicrosoftSQLServer MariaDB Firebase Firestore CockroachDB
  InfluxDB TimescaleDB                                                                            # Deployment & DevOps
  Docker Kubernetes Jenkins GitLab Terraform Ansible Puppet Chef AWS Azure
  GCP Heroku DigitalOcean Cloudflare Vercel Netlify OpenStack Rancher                             ArgoCD Spinnaker
                                                  # Backend Frameworks
  Node.js Express.js Django Flask RubyOnRails SpringBoot Laravel ASP.NET
  Phoenix FastAPI Nest.js Koa.js Hapi.js Sails.js Meteor.js
                                                  # Frontend Frameworks
  React Vue.js Angular Next.js Nuxt.js Svelte SvelteKit Ember.js Backbone.js
  Gatsby jQuery Bootstrap TailwindCSS Bulma Foundation SemanticUI "Element UI"
                                                # Authentication & Authorization
  OAuth JWT Okta Auth0 Keycloak CAS SAML OpenIDConnect LDAP ActiveDirectory
  PingIdentity ForgeRock Duo                    
  # Programming Languages                         Java Python PHP Ruby JavaScript TypeScript Go Rust Elixir Scala Kotlin                          Swift Dart Perl
                                                  # Mobile Frameworks
  ReactNative Flutter Ionic Cordova Xamarin NativeScript                                        
  # E-commerce Platforms                          WooCommerce BigCommerce SalesforceCommerceCloud OracleCommerce IBMWebSphereCommerce
  Shopware OpenCart ZenCart                                                                       # Security Tools
  HashiCorpVault CloudflareZeroTrust BeyondCorp CrowdStrike PaloAltoPrismaCloud                   Qualys Nessus BurpSuite OWASPZAP
                                                  # Message Queues & Streaming                    RabbitMQ Kafka ActiveMQ AmazonSQS RedisPubSub ZeroMQ NATS                                                                                       # Search Engines
  Solr Algolia MeiliSearch AzureSearch AWSCloudSearch                                           
  # File Storage                                  AmazonS3 GoogleCloudStorage AzureBlobStorage Minio Ceph
                                                  # Blockchain & Web3                             Ethereum Solana Polygon Hyperledger Web3.js Ethers.js Hardhat Truffle                         )                                               
is_allowed() {                                    local tech="$1"                                 for allowed in "${WHITELIST[@]}"; do
    if [[ "$tech" == "$allowed" ]]; then              return 0                                      fi
  done                                            return 1                                      }
                                                random_ip() { echo $((RANDOM%256)).$((RANDOM%256)).$((RANDOM%256)).$((RANDOM%256)); }
get_random_ua() {                                 local uas=(                                       "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"                                  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
    "curl/7.68.0"                                   "Wget/1.20"                                   )
  echo "${uas[RANDOM % ${#uas[@]}]}"            }                                               
init_db() {                                       if [[ ! -f "$DB_FILE" ]]; then                    sqlite3 "$DB_FILE" "CREATE TABLE results (id INTEGER PRIMARY KEY, domain TEXT, tech TEXT, timestamp DATETIME DEFAULT CURRENT_TIMESTAMP, UNIQUE(domain, tech));"
    sqlite3 "$DB_FILE" "CREATE INDEX idx_tech ON results(tech);"                                    sqlite3 "$DB_FILE" "CREATE INDEX idx_domain ON results(domain);"                              fi                                            }
                                                insert_db() {                                     local domain="$1"
  local tech="$2"                                 sqlite3 "$DB_FILE" "INSERT OR IGNORE INTO results (domain, tech) VALUES ('$domain','$tech');"
}                                                                                               make_api_request() {
  local domain="$1"                               local max_retries=3                             local retry_count=0
  local delay=5                                                                                   while [ $retry_count -lt $max_retries ]; do
    RESP=$(curl -s -X POST "https://api.ful.io/domain-search" \                                       -H "User-Agent: $(get_random_ua)" \
      -H "X-Forwarded-For: $(random_ip)" \            -H "Accept: application/json" \                 --form "url=$domain" \
      --connect-timeout 15 \                          --max-time 30 \                                 --retry $max_retries \
      --retry-delay $delay)                     
    if [ $? -eq 0 ] && [ -n "$RESP" ]; then           echo "$RESP"                                    return 0
    fi                                              ((retry_count++))                               sleep $delay
  done                                            echo -e "${RED}Failed to retrieve data for $domain after $max_retries attempts${NC}" >&2        return 1
}                                               
if [[ $# -ne 1 ]]; then                           echo -e "${YELLOW}Usage: $0 <Subdomains-file>${NC}"                                             exit 1
fi                                              
DOMAIN_FILE="$1"                                init_db
echo -e "${GREEN}Scanning domains from: ${DOMAIN_FILE}${NC}"
                                                while IFS= read -r DOMAIN; do                     DOMAIN="${DOMAIN// /}"
  [[ -z "$DOMAIN" ]] && continue                  CLEAN_DOMAIN=${DOMAIN#*//}                      CLEAN_DOMAIN=${CLEAN_DOMAIN//\//-}
  echo -e "${CYAN}[*] Scanning $DOMAIN...${NC}"                                                   RESP=$(make_api_request "$DOMAIN")
  if [ $? -ne 0 ]; then                             continue                                      fi
                                                  echo "$RESP" | jq . > "$OUTPUT_DIR/$CLEAN_DOMAIN.json" 2>/dev/null
                                                  TECHS=$(echo "$RESP" | jq -r '.technologies[].technologies[].name?' 2>/dev/null | sort -u)
  if [[ -z "$TECHS" || "$TECHS" == "null" ]]; then                                                  echo -e "${YELLOW}No tech found for $DOMAIN${NC}"                                               continue                                      fi
                                                  echo -e "${GREEN}Technologies found:${NC}"      while IFS= read -r TECH; do
    if [[ -n "$TECH" ]] && is_allowed "$TECH"; then                                                   echo -e "${GREEN}- $TECH${NC}"
      echo "$DOMAIN" >> "$OUTPUT_DIR/${TECH// /_}.txt"                                                insert_db "$DOMAIN" "$TECH"
    else                                              echo -e "${YELLOW}- $TECH ${NC}"              fi
  done <<< "$TECHS"                               echo ""                                       done < "$DOMAIN_FILE"
                                                echo -e "${GREEN}Scan complete. Summary:${NC}"  sqlite3 "$DB_FILE" "SELECT tech, COUNT(DISTINCT domain) AS count FROM results GROUP BY tech ORDER BY count DESC;"
