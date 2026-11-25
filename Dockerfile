FROM swipl:stable
WORKDIR /app
COPY . .
RUN chmod -R a+rX /app
ENV PORT=10000
EXPOSE 10000
CMD ["swipl","server.pl"]
