USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspDuplicateItemDelete2
	CreatedBy: Larry Dugger
	Descr: This procedure will delete if found
	Tables: [mac].[DuplicateItem]
		,[stat].[NewDuplicateItem]
		,[payer].[Payer]
	Functions: [ifa].[ufnDuplicateItemMac]
   
	History:
		2018-08-18 - LBD - Created
		2018-05-09 - LBD - Modified, took out direct link to Condensed.	
		2019-05-01 - LBD - Modified, uses new [mac].[DuplicateItem] table
*****************************************************************************************/
ALTER PROCEDURE [condensed].[uspDuplicateItemDelete2](
     @pbiPayerId BIGINT
	,@pnvCheckNumber NVARCHAR(50)
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @ncRoutingNumber nchar(9)
		,@nvAccountNumber nvarchar(50) = ''
		,@vbIdMac varbinary(32)
	
	SELECT @ncRoutingNumber = RoutingNumber
		,@nvAccountNumber = AccountNumber
	FROM [payer].[Payer] WITH (READUNCOMMITTED)
	WHERE PayerId = @pbiPayerId;

	SET @vbIdMac = [ifa].[ufnDuplicateItemMac](@ncRoutingNumber, @nvAccountNumber, @pnvCheckNumber);
	--Main table
	DELETE di
	--2019-05-01 FROM [stat].[DuplicateItem] di
	FROM [mac].[DuplicateItem] di
	WHERE IdMac = @vbIdMac;
	--Just in case it is in the queue
	DELETE di
	FROM [stat].[NewDuplicateItem] di
	WHERE IdMac = @vbIdMac;

END

