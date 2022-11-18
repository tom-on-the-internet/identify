package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"strings"

	"github.com/aws/aws-lambda-go/lambda"
	echoadapter "github.com/awslabs/aws-lambda-go-api-proxy/echo"
	"github.com/labstack/echo/v4"
	"github.com/labstack/echo/v4/middleware"
	"golang.org/x/exp/slices"
)

// Visit is the record of a client using the redirect.
type Visit struct {
	Country string `json:"country"`
	City    string `json:"city"`
}

func main() {
	e := echo.New()
	e.Use(middleware.Logger())

	e.GET("/", handle)

	if isRunningInLambda() {
		echoProxy := echoadapter.New(e).ProxyWithContext
		lambda.Start(echoProxy)
	} else {
		log.Fatal(e.Start(":8888"))
	}
}

func isRunningInLambda() bool {
	return strings.TrimSpace(os.Getenv("AWS_LAMBDA_FUNCTION_NAME")) != ""
}

func handle(c echo.Context) error {
	if !isOriginAllowed(c.Request()) {
		return echo.NewHTTPError(http.StatusForbidden, "No")
	}

	ipAddress := strings.Split(c.Request().RemoteAddr, ":")[0]

	visit := Visit{}

	res, err := http.Get("http://ip-api.com/json/" + ipAddress)
	if err != nil {
		return echo.NewHTTPError(http.StatusForbidden, "No")
	}

	defer res.Body.Close()

	err = json.NewDecoder(res.Body).Decode(&visit)
	if err != nil {
		return echo.NewHTTPError(http.StatusForbidden, "No")
	}

	c.Response().Header().Set("Content-Type", "application/json")
	c.Response().Header().Add("Access-Control-Allow-Origin", getOrigin(c.Request()))
	c.Response().Header().Add("Access-Control-Allow-Credentials", "true")
	c.Response().
		Header().
		Add("Access-Control-Allow-Headers", "Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization, accept, origin, Cache-Control, X-Requested-With")
	c.Response().Header().Add("Access-Control-Allow-Methods", "GET")

	return c.JSON(http.StatusOK, visit)
}

func getOrigin(r *http.Request) string {
	origins, ok := r.Header["Origin"]
	if !ok || len(origins) == 0 {
		return ""
	}

	return origins[0]
}

func isOriginAllowed(r *http.Request) bool {
	origin := getOrigin(r)
	origin = strings.TrimSuffix(origin, "/")

	allowedOrigins := []string{
		"https://tomontheinternet.com",
		"https://www.tomontheinternet.com",
		"http://127.0.0.1:8080",
		"https://www.jpedmedia.com",
		"https://jpedmedia.com",
	}

	return slices.Contains(allowedOrigins, origin)
}
