PEM=.pem
CRT=.crt
CRT_DIR=./cert-pub
KEY=.key
KEY_DIR=./cert-keys
REQ=.csr
REQ_DIR=./cert-reqs
DK=.pem
DKPUB=-pub.pem
DK_DIR=./dkim
DK_BITS=1024
OPENSSL_CONF=./openssl.cnf
PKCS7=.pkcs7
KEYSTORE_DIR=./keystore
KEYTOOL=keytool
KEYSTORE=.jks
KEY_ALIAS ?= tomcat
KS ?= $(KEY_ALIAS)-$(CN)
KS_BITS=4096
KS_VALIDITY=1825
CERT_OU="My Org Unit"
CERT_O="My Org"
CERT_L="My Location"
CERT_ST="My State"
CERT_C="My Country"

tomcat-gen: KS=tomcat-$(CN)
tomcat-add: KS=tomcat-$(CN)
tomcat-add-signed: KS=tomcat-$(CN)

help default:
	@echo Pick a target:
	@echo
	@echo "   cert     -- create a new self-signed server certificate"
	@echo "   dk       -- create a new DomainKey (for use by PowerMTA)"
	@echo "   dkview   -- view a DomainKey and suggested TXT record"
	@echo "   req      -- create a server certificate request"
	@echo "   renew    -- renew a server's certificate"
	@echo "   revoke   -- remove authorization for a server's cert"
	@echo "   sign     -- sign a server's certificate request"
	@echo "   view     -- view the contents of a server certificate"
	@echo "   view-req -- view the contents of a Certificate Signing Request"
	@echo "   decrypt  -- strip the key phrase from a private key"
	@echo "   encrypt  -- set a new key phrase on a private key"
	@echo "   convert-pkcs7   -- convert a PKCS7 cert to PEM format"
	@echo ""
	@echo "Java keystore targets:"
	@echo "   ks-gen*           -- generate a new Java keystore"
	@echo "   ks-import*        -- import a cert into a Java keystore"
	@echo "   ks-export*        -- export public cert and store in separate file"
	@echo "   ks-export-key*    -- export private cert and store in separate file"
	@echo "   ks-req*           -- generate a new CSR from a Java keystore"
	@echo "   ks-replace*       -- replace a certificate"
	@echo "   ks-list           -- show all stored certs"
	@echo "   ks-show           -- print an exported cert"
	@echo ""
	@echo "   * Target requires:"
	@echo "       KEY_ALIAS=<alias>"
	@echo "   Optional:"
	@echo "       KS=<keystore_file>, KS_BITS=<num_bits>, KS_VALIDITY=<num_days>"
	@echo ""
	@echo "Java keystore targets for Tomcat:"
	@echo "   tomcat-gen        -- generate a new Java keystore"
	@echo "   tomcat-req        -- generate a new certificate signing request"
	@echo "   tomcat-add        -- import a signed root or intermediate cert"
	@echo "                        into a Tomcat keystore"
	@echo "                        (requires CERT=<path> to import the cert,"
	@echo "                        KEY_ALIAS=<alias> to assign it a name)"
	@echo "   tomcat-add-signed -- import the signed Tomcat certificate"
	@echo
	@echo "All commands require setting CN=<hostname> to work with hostname's cert."

cert:	req sign

convert-pkcs7:
	openssl pkcs7 -print_certs -in "$(CRT_DIR)/$(CN)$(PKCS7)" -out "$(CRT_DIR)/$(CN)$(CRT)"
	@echo "Your PKCS7 cert has been converted to PEM format"
	@echo "The new server certificate is $(CRT_DIR)/$(CN)$(CRT)."
	@echo ""

req:	testcn
	@echo "Requesting a server certificate for $(CN)."
	openssl req -config $(OPENSSL_CONF) -new -out "$(REQ_DIR)/$(CN)$(REQ)" -keyout "$(KEY_DIR)/$(CN)$(KEY)" -subj "/CN=$(CN)/OU=$(CERT_OU)/O=$(CERT_O)/L=$(CERT_L)/ST=$(CERT_ST)/C=$(CERT_C)"
	@echo "Your new server certificate request is $(REQ_DIR)/$(CN)$(REQ)."

renew-only:
	@[ -f $(CRT_DIR)/$(CN)$(CRT) ] || \
	 { echo "no cert exists for $(CN)"; exit 1; }
	@[ -f $(REQ_DIR)/$(CN)$(REQ) ] || \
	 { echo "no cert request exists for $(CN)"; exit 1; }
	openssl ca -config $(OPENSSL_CONF) -policy policy_anything \
	 -out $(CRT_DIR)/$(CN)$(CRT) -infiles $(REQ_DIR)/$(CN)$(REQ)

renew:	testcn revoke
	@[ -f $(CRT_DIR)/$(CN)$(CRT) ] || \
	 { echo "no cert exists for $(CN)"; exit 1; }
	@[ -f $(REQ_DIR)/$(CN)$(REQ) ] || \
	 { echo "no cert request exists for $(CN)"; exit 1; }
	sudo openssl ca -config $(OPENSSL_CONF) -policy policy_anything \
	 -out "$(CRT_DIR)/$(CN)$(CRT)" -infiles "$(REQ_DIR)/$(CN)$(REQ)"

revoke:	testcn
	@[ -f $(CRT_DIR)/$(CN)$(CRT) ] || \
	 { echo "no cert exists for $(CN)"; exit 1; }
	openssl ca -config $(OPENSSL_CONF) -revoke $(CRT_DIR)/$(CN)$(CRT) 

sign:	testcn
	@echo "Signing the certificate request for $(CN)."
	openssl ca -config $(OPENSSL_CONF) -out "$(CRT_DIR)/$(CN)$(CRT)" -in "$(REQ_DIR)/$(CN)$(REQ)"
	@echo "Your new self-signed keyless certificate is $(CRT_DIR)/$(CN)$(CRT)."
	@echo "Your certificate's private key is $(KEY_DIR)/$(CN)$(KEY)."

decrypt:
	openssl rsa -in "$(KEY_DIR)/$(CN)$(KEY)" -out "$(KEY_DIR)/$(CN)$(KEY).noenc"
	@echo "Your private key has been stripped of its pass phrase."
	@echo "The new, open keyfile is $(KEY_DIR)/$(CN)$(KEY).noenc"
	@echo ""

encrypt:
	openssl rsa -des3 -in "$(KEY_DIR)/$(CN)$(KEY).noenc" -out "$(KEY_DIR)/$(CN)$(KEY).enc"
	@echo "Your private key has been encrypted."
	@echo "The encrypted keyfile is $(KEY_DIR)/$(CN)$(KEY).enc"

view:	testcn
	openssl x509 -text -noout -in "$(CRT_DIR)/$(CN)$(CRT)"

view-req:	testcn
	openssl req -text -noout -in "$(REQ_DIR)/$(CN)$(REQ)"

testcn:
	@[ -n "$(CN)" ] || \
	 { echo "No common name given.  Please set CN=hostname"; exit 1; }

dk: dkgen dkview

dkgen:
	@echo "Generating a DomainKey for $(CN)."
	@openssl genrsa -out "$(DK_DIR)/$(CN)$(DK)" $(DK_BITS) 2>/dev/null
	@echo "Your new private DomainKey is in $(DK_DIR)/$(CN)$(DK)."
	openssl rsa -in "$(DK_DIR)/$(CN)$(DK)" -pubout 2>/dev/null |grep -v ^----- |tr -d '\n' > "$(DK_DIR)/$(CN)$(DKPUB)"
	@echo "The private key is in $(DK_DIR)/$(CN)$(DK)."
	@echo "The public key is in $(DK_DIR)/$(CN)$(DKPUB)."
	@echo ""
	@echo ""

dkview:
	@echo "Public DomainKey for $(CN):"
	@openssl rsa -in "$(DK_DIR)/$(CN)$(DK)" -pubout 2>/dev/null |grep -v ^----- |tr -d '\n' |sed 's,$$,\n,'
	@echo ""
	@echo "Suggested DNS entry:"
	@printf "%s 86400 IN TXT \"k=rsa\\; p=%s\\;\"\n" "`echo $(CN) |sed 's,\.,._domainkey.,'`" "`cat $(DK_DIR)/$(CN)$(DKPUB)`"
	@echo ""

verify:
	@(openssl x509 -noout -modulus -in "$(CRT_DIR)/$(CN).$(CRT)" | openssl md5; openssl rsa -noout -modulus -in "$(KEY_DIR)/$(CN).$(KEY)" | openssl md5) | uniq


##
## Managing Tomcat Java keystores
##
## See also:
##     http://tomcat.apache.org/tomcat-7.0-doc/ssl-howto.html#Installing_a_Certificate_from_a_Certificate_Authority
##

# Generate a new keystore
tomcat-gen:
	@[ -n "$(CN)" ] || { echo "Missing CN=cert_name"; exit 1; }
	@echo "==> Generating a new tomcat key for $(KS)$(KEYSTORE)"
	@$(KEYTOOL) -genkey -alias tomcat -keyalg RSA -keysize $(KS_BITS) -keystore "$(KEYSTORE_DIR)/$(KS)$(KEYSTORE)" -dname "CN=$(CN), OU=\"$(CERT_OU)\", O=\"$(CERT_O)\", L=\"$(CERT_L)\", S=\"$(CERT_ST)\", C=\"$(CERT_C)\""
	@echo "--> Keystore for $(CN) is $(KEYSTORE_DIR)/$(KS)$(KEYSTORE)"
	@echo ""

# Export a certificate signing request
tomcat-req:
	@[ -n "$(CN)" ] || { echo "Missing CN=cert_name"; exit 1; }
	@$(KEYTOOL) -certreq -alias tomcat -keyalg RSA -keysize $(KS_BITS) -keystore "$(KEYSTORE_DIR)/$(KS)$(KEYSTORE)" -file "$(REQ_DIR)/$(CN)$(REQ)"
	@echo "--> New CSR for $(CN) is in $(REQ_DIR)/$(CN)$(REQ)"
	@cat "$(REQ_DIR)/$(CN)$(REQ)"
	@echo ""

# Import a signed root or intermediate certificate into a Tomcat keystore
tomcat-add:
	@[ -n "$(CN)" ] || { echo "Missing CN=cert_name"; exit 1; }
	@[ -n "$(KEY_ALIAS)" ] || { echo "Missing KEY_ALIAS=alias"; exit 1; }
	@echo "==> Importing a chain certificate for $(KEY_ALIAS)"
	@echo "    into Java keystore $(KS)$(KEYSTORE)"
	@echo "--> Removing existing alias '$(KEY_ALIAS)' from Java keystore."
	$(KEYTOOL) -keystore "$(KEYSTORE_DIR)/$(KS)$(KEYSTORE)" -alias "$(KEY_ALIAS)" -delete || true
	@echo "--> Importing signed cert for $(CN)"
	@echo "     into Java keystore $(KS)."
	@echo "--> The private key and the keystore must have the same password."
	@$(KEYTOOL) -import -trustcacerts -alias "$(KEY_ALIAS)" -keystore "$(KEYSTORE_DIR)/$(KS)$(KEYSTORE)" -file "$(CERT)"
	@echo ""

# Import a signed tomcat certificate into a keystore
tomcat-add-signed:
	@[ -n "$(CN)" ] || { echo "Missing CN=cert_name"; exit 1; }
	@echo "==> Importing a signed certificate for $(CN)"
	@echo "    into Java keystore $(KS)$(KEYSTORE)."
	@echo "--> The private key and the keystore must have the same password."
	@$(KEYTOOL) -import -alias tomcat -keystore "$(KEYSTORE_DIR)/$(KS)$(KEYSTORE)" -file "$(CRT_DIR)/$(CN)$(CRT)"
	@echo ""
	@echo "--> Your Tomcat Java keystore is ready to go:"
	@echo "    $(KEYSTORE_DIR)/$(KS)$(KEYSTORE)"
	@echo ""


##
## Generic keystore targets
##
## See also:
##   http://docs.oracle.com/javase/6/docs/technotes/tools/solaris/keytool.html
##

ks-gen:
	@[ -n "$(CN)" ] || { echo "Missing CN=cert_name"; exit 1; }
	@[ -n "$(KEY_ALIAS)" ] || { echo "Missing KEY_ALIAS=alias"; exit 1; }
	@echo "==> Generating a new keystore for $(KS)$(KEYSTORE)"
	@echo "    alias=$(KEY_ALIAS)"
	@echo "    bits=$(KS_BITS)"
	@echo "    valid=$(KS_VALIDITY)"
	@$(KEYTOOL) -genkey -alias '$(KEY_ALIAS)' -keyalg RSA -keysize $(KS_BITS) -keystore "$(KEYSTORE_DIR)/$(KS)$(KEYSTORE)" -dname "CN=$(CN), OU=\"$(CERT_OU)\", O=\"$(CERT_O)\", L=\"$(CERT_L)\", S=\"$(CERT_ST)\", C=\"$(CERT_C)\"" -validity $(KS_VALIDITY)
	@echo "--> Keystore for $(CN) is $(KEYSTORE_DIR)/$(CN)$(KEYSTORE)"
	@echo ""

# Delete then import a signed certificate
ks-replace:
	@[ -n "$(CN)" ] || { echo "Missing CN=cert_name"; exit 1; }
	@[ -n "$(KEY_ALIAS)" ] || { echo "Missing KEY_ALIAS=alias"; exit 1; }
	@echo "==> Removing existing alias '$(KEY_ALIAS)' from $(KS)$(KEYSTORE)"
	$(KEYTOOL) -keystore "$(KEYSTORE_DIR)/$(KS)$(KEYSTORE)" -alias "$(KEY_ALIAS)" -delete || true
	@echo ""
	@echo "==> Importing signed cert for $(CN) into Java keystore for $(KS)."
	@echo "The private key and the keystore must have the same password."
	$(KEYTOOL) -import -trustcacerts -alias "$(KEY_ALIAS)" -keystore "$(KEYSTORE_DIR)/$(KS)$(KEYSTORE)" -file "$(CRT_DIR)/$(CN)$(CRT)"
	@echo ""

# Import a signed certificate
ks-add:
	@[ -n "$(CN)" ] || { echo "Missing CN=cert_name"; exit 1; }
	@[ -n "$(KEY_ALIAS)" ] || { echo "Missing KEY_ALIAS=alias"; exit 1; }
	@echo "==> Importing signed cert for $(CN) into Java keystore for $(KS)."
	@echo "The private key and the keystore must have the same password."
	$(KEYTOOL) -import -trustcacerts -alias "$(KEY_ALIAS)" -keystore "$(KEYSTORE_DIR)/$(KS)$(KEYSTORE)" -file "$(CRT_DIR)/$(CN)$(CRT)"
	@echo ""

# Export a certificate signing request
ks-req:
	@[ -n "$(CN)" ] || { echo "Missing CN=cert_name"; exit 1; }
	@[ -n "$(KEY_ALIAS)" ] || { echo "Missing KEY_ALIAS=alias"; exit 1; }
	@echo "==> Generating certificate signing request from $(KS)$(KEYSTORE)"
	@$(KEYTOOL) -certreq -alias "$(KEY_ALIAS)" -keystore "$(KEYSTORE_DIR)/$(KS)$(KEYSTORE)" -file "$(REQ_DIR)/$(CN)$(REQ)" -v
	@echo "--> New CSR for $(CN) is in $(REQ_DIR)/$(CN)$(REQ)"
	@cat "$(REQ_DIR)/$(CN)$(REQ)"
	@echo ""

ks-list:
	@[ -n "$(CN)" ] || { echo "Missing CN=cert_name"; exit 1; }
	@echo "==> Listing Java keystore $(KS)$(KEYSTORE)"
	@$(KEYTOOL) -list -keystore "$(KEYSTORE_DIR)/$(KS)$(KEYSTORE)"

ks-export:
	@[ -n "$(CN)" ] || { echo "Missing CN=cert_name"; exit 1; }
	@[ -n "$(KEY_ALIAS)" ] || { echo "Missing KEY_ALIAS=alias"; exit 1; }
	@echo "==> Exporting certificate from $(KS)$(KEYSTORE)"
	@echo "Certificate will be stored in $(CRT_DIR)/$(CN)$(CRT) "
	@$(KEYTOOL) -exportcert -rfc -alias "$(KEY_ALIAS)" -file "$(CRT_DIR)/$(CN)$(CRT)" -keystore "$(KEYSTORE_DIR)/$(KS)$(KEYSTORE)"

ks-export-key:
	@[ -n "$(CN)" ] || { echo "Missing CN=cert_name"; exit 1; }
	@[ -n "$(KEY_ALIAS)" ] || { echo "Missing KEY_ALIAS=alias"; exit 1; }
	@echo "==> Exporting private certificate from $(KS)$(KEYSTORE)"
	@echo "Certificate will be stored in $(KEY_DIR)/$(CN)$(KEY) "
	$(KEYTOOL) -importkeystore -srckeystore "$(KEYSTORE_DIR)/$(KS)$(KEYSTORE)" -srcalias "$(KEY_ALIAS)" -srcstoretype JKS -destkeystore "$(KEY_DIR)/$(CN).p12" -deststoretype PKCS12
	openssl pkcs12 -in "$(KEY_DIR)/$(CN).p12" -out "$(KEY_DIR)/$(CN).key" -nocerts
	@rm "$(KEY_DIR)/$(CN).p12"

ks-show:
	@[ -n "$(CN)" ] || { echo "Missing CN=cert_name"; exit 1; }
	@$(KEYTOOL) -printcert -file "$(CRT_DIR)/$(CN)$(CRT)"
