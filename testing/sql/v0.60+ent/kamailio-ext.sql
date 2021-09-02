--
-- Table structure for table `dsip_cdrinfo`
--

DROP TABLE IF EXISTS `dsip_cdrinfo`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `dsip_cdrinfo` (
  `gwgroupid` varchar(64) NOT NULL,
  `email` varchar(128) DEFAULT NULL,
  `send_interval` int(10) unsigned  NULL DEFAULT '',
  `last_send` datetime DEFAULT NULL,
  PRIMARY KEY (`gwgroupid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

LOCK TABLES `dsip_cdrinfo` WRITE;
/*!40000 ALTER TABLE `dsip_cdrinfo` DISABLE KEYS */;
/*!40000 ALTER TABLE `dsip_cdrinfo` ENABLE KEYS */;
UNLOCK TABLES;