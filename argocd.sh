pw=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

echo "===================== FERTIG =====================\n"
echo "ArgoCD Login:  admin  /  $pw"
echo "Dashboard:     kubectl port-forward svc/argocd-server -n argocd 8080:443   -> https://localhost:8080"
echo "App-URL:       kubectl get svc ingress-nginx-controller -n ingress-nginx   (EXTERNAL-IP)"
echo "=================================================\n"

